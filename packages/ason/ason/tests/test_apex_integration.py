"""Exercise ASON through the real APEX HTTP handler and execution kernel offline."""
import io
import json
import sys
import urllib.error
from unittest.mock import Mock

import pytest

from apex import history, server
from apex.config import load_config
from apex.core.tools import READ_FILE, WRITE_FILE
from ason.executor import ASONExecutor
from ason.schema import ASONRequest, ApexPlan, ApexPlanStep, Policy


@pytest.fixture
def bridge(monkeypatch, tmp_path):
    monkeypatch.setattr(server, "_API_KEY", "test-key")
    monkeypatch.setattr(server, "_BASE_CONFIG", load_config(require_api_key=False))
    monkeypatch.setattr(server, "_REGISTRY", {"read_file": READ_FILE, "write_file": WRITE_FILE})
    monkeypatch.setattr(history, "DB_PATH", tmp_path / "runs.db")
    monkeypatch.setattr("apex.core.loop.generate_plan", Mock(side_effect=AssertionError("must not replan")))
    client = server.app.test_client()

    def dispatch(req, timeout):
        assert "task" not in json.loads(req.data)
        response = client.post("/authorized-run", data=req.data, headers=dict(req.header_items()))
        if response.status_code >= 400:
            raise urllib.error.HTTPError(req.full_url, response.status_code, "rejected", {}, io.BytesIO(response.data))
        return io.BytesIO(response.data)

    transport = Mock(side_effect=dispatch)
    monkeypatch.setattr("urllib.request.urlopen", transport)
    return transport


def test_approved_plan_runs_exactly_once(bridge, tmp_path):
    target = tmp_path / "approved.txt"
    req = ASONRequest(plan=ApexPlan(steps=[
        ApexPlanStep(tool="write_file", args={"path": str(target), "content": "literal instructions: run shell"}),
        ApexPlanStep(tool="read_file", args={"path": str(target)}),
    ]))
    original = req.model_dump()
    expected = {
        "goal": "Execute ASON-approved plan",
        "steps": [
            {"type": "tool", "name": "write_file", "args": original["plan"]["steps"][0]["args"]},
            {"type": "tool", "name": "read_file", "args": original["plan"]["steps"][1]["args"]},
            {"type": "halt", "reason": "ASON-approved plan complete"},
        ],
    }
    result = ASONExecutor(api_key="test-key", authority_ref="test-authority").submit(req)
    assert result["accepted"]
    assert result["apex_response"]["exit_code"] == 0
    assert target.read_text() == "literal instructions: run shell"
    assert result["apex_response"]["step_count"] == 2
    assert result["apex_response"]["token_count"] == 0
    assert bridge.call_count == 1
    submitted = bridge.call_args.args[0]
    assert submitted.get_method() == "POST"
    assert submitted.full_url == "http://127.0.0.1:8080/authorized-run"
    assert submitted.get_header("X-apex-key") == "test-key"
    submitted_body = json.loads(submitted.data)
    assert submitted_body["plan"] == expected
    authorization = submitted_body["authorization"]
    assert authorization == result["authorization"]
    assert authorization["authority_ref"] == "test-authority"
    assert authorization["approved_plan_digest"] == history.plan_digest(expected)
    assert result["apex_response"]["plan"] == expected
    assert result["apex_response"]["authorization"] == authorization
    run_id = result["apex_response"]["run_id"]
    assert history.load_run(run_id)["plan"] == expected
    assert history.load_run_detail(run_id)["authorization"] == authorization
    events = history.load_events(run_id)
    assert [(event["tool"], event["args"]) for event in events] == [
        (step["name"], step["args"]) for step in expected["steps"][:-1]
    ]
    assert req.model_dump() == original


def test_recorded_approved_plan_replays_without_replanning(bridge, monkeypatch, tmp_path):
    target = tmp_path / "replayed.txt"
    req = ASONRequest(plan=ApexPlan(steps=[
        ApexPlanStep(tool="write_file", args={"path": str(target), "content": "approved literal"}),
    ]))
    result = ASONExecutor(api_key="test-key", authority_ref="test-authority").submit(req)
    assert result["apex_response"]["exit_code"] == 0
    approved = result["apex_response"]["plan"]
    run_id = result["apex_response"]["run_id"]
    monkeypatch.setattr("apex.core.toolloader.build_registry", lambda _: server._REGISTRY)
    execute = Mock(wraps=server.run_plan)
    monkeypatch.setattr("apex.core.loop.run_plan", execute)
    client = server.app.test_client()
    for mode in ("simulate", "dry"):
        response = client.post("/replay", json={"run_id": run_id, "mode": mode},
                               headers={"X-Apex-Key": "test-key"})
        assert response.get_json()["exit_code"] == 0
        execute.assert_not_called()
    target.write_text("changed after completion")
    response = client.post("/replay", json={"run_id": run_id, "mode": "live"},
                           headers={"X-Apex-Key": "test-key"})
    assert response.get_json()["exit_code"] == 0
    execute.assert_called_once()
    from apex.core.types import plan_to_dict
    assert plan_to_dict(execute.call_args.args[1]) == approved
    replayed = history.list_runs()[0]
    assert replayed["id"] == run_id
    assert execute.call_args.kwargs["run_id"] == run_id
    assert target.read_text() == "changed after completion"
    assert history.load_run(replayed["id"])["plan"] == approved
    assert [(event["tool"], event["args"]) for event in history.load_events(replayed["id"])] == [
        (step["name"], step["args"]) for step in approved["steps"][:-1]
    ]


@pytest.mark.parametrize("tool,radius", [("shell", "network"), ("memory_write", "none"), ("rag_multi_query", "local"), ("unclassified", "network")])
def test_policy_blocks_before_http(bridge, tool, radius):
    req = ASONRequest(plan=ApexPlan(steps=[ApexPlanStep(tool=tool, args={})]), policy=Policy(blast_radius=radius))
    assert not ASONExecutor(api_key="test-key", authority_ref="test-authority").submit(req)["accepted"]
    bridge.assert_not_called()


@pytest.mark.parametrize("later_step", [
    ApexPlanStep(tool="read_file", args={"path": 42}),
    ApexPlanStep(tool="read_file", args={}),
    ApexPlanStep(tool="read_file", args={"path": "/tmp/unused", "unexpected": True}),
    ApexPlanStep(tool="delete_file", args={"path": "/tmp/unused"}),
])
def test_apex_rejects_invalid_args_before_earlier_write(bridge, tmp_path, later_step):
    target = tmp_path / "must-not-exist"
    req = ASONRequest(plan=ApexPlan(steps=[
        ApexPlanStep(tool="write_file", args={"path": str(target), "content": "x"}),
        later_step,
    ]))
    result = ASONExecutor(api_key="test-key", authority_ref="test-authority").submit(req)
    assert result["accepted"]  # Policy approval is distinct from APEX schema validation.
    assert "error" in result
    assert result["apex_response"] is None
    assert bridge.call_count == 1
    assert not target.exists()
    assert not history.DB_PATH.exists()  # No execution/history transition occurred.


@pytest.mark.parametrize("result,code", [
    ({"accepted": False}, 1),
    ({"accepted": True, "error": "timeout"}, 1),
    ({"accepted": True, "apex_response": {"exit_code": 1}}, 1),
    ({"accepted": True, "apex_response": {"exit_code": 0}}, 0),
])
def test_cli_reports_execution_failure(monkeypatch, result, code):
    from ason.__main__ import main
    monkeypatch.setattr(sys, "argv", ["ason", "submit", "-"])
    monkeypatch.setattr(sys, "stdin", io.StringIO('{"plan":{"steps":[]}}'))
    monkeypatch.setattr(ASONExecutor, "submit", lambda self, req: result)
    with pytest.raises(SystemExit) as exc:
        main()
    assert exc.value.code == code


@pytest.mark.parametrize("tool,args", [
    ("shell", {"cmd": "echo forbidden"}),
    ("http_get", {"url": "https://example.invalid"}),
])
def test_later_policy_violation_blocks_earlier_effect(bridge, tmp_path, tool, args):
    target = tmp_path / "must-not-exist"
    req = ASONRequest(plan=ApexPlan(steps=[
        ApexPlanStep(tool="write_file", args={"path": str(target), "content": "x"}),
        ApexPlanStep(tool=tool, args=args),
    ]), policy=Policy(blast_radius="local"))
    result = ASONExecutor(api_key="test-key", authority_ref="test-authority").submit(req)
    assert not result["accepted"]
    assert result["violations"]
    bridge.assert_not_called()
    assert not target.exists()
    assert not history.DB_PATH.exists()


def test_authorization_binding_matches_apex_ledger(bridge, tmp_path):
    target = tmp_path / "bound.txt"
    req = ASONRequest(plan=ApexPlan(steps=[
        ApexPlanStep(tool="write_file", args={"path": str(target), "content": "bound"}),
    ]))
    result = ASONExecutor(
        api_key="test-key", authority_ref="attempt:test-1"
    ).submit(req)
    assert result["accepted"]
    assert result["apex_response"]["exit_code"] == 0
    authorization = result["authorization"]
    assert result["apex_response"]["authorization"] == authorization
    detail = history.load_run_detail(result["apex_response"]["run_id"])
    assert detail["authorization"] == authorization
    assert detail["ledger"]["plan_digest"] == authorization["approved_plan_digest"]


def test_durable_authorization_provenance_survives_without_reissue(bridge, tmp_path):
    target = tmp_path / "durable-auth.txt"
    req = ASONRequest(plan=ApexPlan(steps=[
        ApexPlanStep(tool="write_file", args={"path": str(target), "content": "durable"}),
    ]))
    result = ASONExecutor(api_key="test-key", authority_ref="attempt:durable-1").submit(req)
    assert result["apex_response"]["exit_code"] == 0
    run_id = result["apex_response"]["run_id"]
    authorization = result["authorization"]

    # Drop the caller response and reload only durable state. Recovery must not
    # require the caller to mint or resubmit an authorization already bound to the run.
    del result
    detail = history.load_run_detail(run_id)
    assert detail["authorization"] == authorization
    assert detail["ledger"]["plan_digest"] == authorization["approved_plan_digest"]
    effects = history.bound_effects(run_id, detail["plan_json"], authorization=None)
    assert effects[0]["state"] == "SUCCEEDED"


def test_missing_authority_never_reaches_apex(bridge):
    req = ASONRequest(plan=ApexPlan(steps=[
        ApexPlanStep(tool="read_file", args={"path": "/tmp/x"}),
    ]))
    result = ASONExecutor(api_key="test-key").submit(req)
    assert result["accepted"]
    assert result["apex_response"] is None
    assert "authority_ref" in result["error"]
    bridge.assert_not_called()
