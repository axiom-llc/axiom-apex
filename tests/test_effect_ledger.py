"""Process-crash boundaries for the SQLite effect ledger (not power-loss tests)."""
import json
import os
import subprocess
import sys
from unittest.mock import Mock

import pytest

from apex import history
from apex.config import load_config
from apex.core import loop
from apex.core.state import format_output
from apex.core.types import Halt, Plan, Tool, ToolCall, plan_to_dict


@pytest.fixture
def setup(monkeypatch, tmp_path):
    monkeypatch.setattr(history, "DB_PATH", tmp_path / "runs.db")
    monkeypatch.setattr(loop, "generate_plan", Mock(side_effect=AssertionError("must not replan")))
    plan = Plan("accepted", (ToolCall("effect", {"label": "one"}),
                             ToolCall("effect", {"label": "two"}), Halt("done")))
    calls = []
    tool = Tool("effect", {"label": str}, {}, lambda args: calls.append(args["label"]) or {"ok": True})
    return plan, {"effect": tool}, calls, load_config(require_api_key=False)


def test_binding_and_intents_are_committed_before_dispatch(setup, monkeypatch):
    plan, registry, calls, config = setup
    original = loop.dispatch_effect

    def dispatch(run_id, step):
        # Independent SQLite connections must see the complete binding and intent.
        record = history.load_run(run_id)
        assert record["plan"] == plan_to_dict(plan)
        assert record["exit_code"] is None
        rows = history.bound_effects(run_id, record["plan"])
        assert len(rows) == 2
        assert rows[step]["state"] == "INTENT_RECORDED"
        assert len(calls) == step
        original(run_id, step)
        assert history.bound_effects(run_id, record["plan"])[step]["state"] == "DISPATCHING"

    monkeypatch.setattr(loop, "dispatch_effect", dispatch)
    state = loop.run_plan("task", plan, config, registry)
    assert state.status == "HALTED"
    assert calls == ["one", "two"]
    assert [r["state"] for r in history.bound_effects(state.run_id, plan_to_dict(plan))] == ["SUCCEEDED"] * 2
    detail = history.load_run_detail(state.run_id)
    assert detail["ledger"] == {"plan_digest": history.plan_digest(plan_to_dict(plan)), "step_count": 3}
    assert detail["registry_binding"] == {
        "contract_digest": history.tool_registry_contract_digest(registry)
    }
    assert [row["state"] for row in detail["effects"]] == ["SUCCEEDED"] * 2


# Each child exits without exception unwinding or SQLite cleanup by Python.
CRASH_SCRIPT = r'''
import json, os, sys
from pathlib import Path
from apex import history
from apex.config import load_config
from apex.core import loop
from apex.core.planner import parse_plan
from apex.core.types import Tool
boundary, target, raw = sys.argv[1:]
def effect(args):
    with Path(target).open("a") as stream:
        stream.write(args["label"] + "\n")
        stream.flush()
    if boundary == "inside_effect":
        os._exit(73)
    return {"ok": True}
registry = {"effect": Tool("effect", {"label": str}, {}, effect)}
name, when = {
    "before_run": ("begin_run", "before"),
    "intents": ("begin_run", "after"),
    "dispatch": ("dispatch_effect", "after"),
    "inside_effect": ("observe_effect", "before"),
    "before_outcome": ("observe_effect", "before"),
    "outcome": ("observe_effect", "after"),
    "before_finish": ("finish_run", "before"),
}[boundary]
original = getattr(loop, name)
def crash(*args, **kwargs):
    if when == "before":
        os._exit(73)
    result = original(*args, **kwargs)
    os._exit(73)
setattr(loop, name, crash)
loop.run_plan("task", parse_plan(raw, registry), load_config(require_api_key=False), registry)
'''


@pytest.mark.parametrize("boundary,expected_state,before,after,status", [
    ("before_run", None, [], [], None),
    ("intents", "INTENT_RECORDED", [], ["one", "two"], "HALTED"),
    ("dispatch", "DISPATCHING", [], [], "ERROR"),
    ("inside_effect", "DISPATCHING", ["one"], ["one"], "ERROR"),
    ("before_outcome", "DISPATCHING", ["one"], ["one"], "ERROR"),
    ("outcome", "SUCCEEDED", ["one"], ["one", "two"], "HALTED"),
    ("before_finish", "SUCCEEDED", ["one", "two"], ["one", "two"], "HALTED"),
])
def test_process_crash_and_repeated_recovery(setup, tmp_path, boundary, expected_state, before, after, status):
    plan, registry, _, config = setup
    target = tmp_path / "effects.txt"
    env = {**os.environ, "APEX_HISTORY_DB_PATH": str(history.DB_PATH)}
    child = subprocess.run([sys.executable, "-c", CRASH_SCRIPT, boundary, str(target),
                            json.dumps(plan_to_dict(plan))], env=env, capture_output=True, text=True, timeout=20)
    assert child.returncode == 73, child.stderr
    read = lambda: target.read_text().splitlines() if target.exists() else []
    assert read() == before
    if expected_state is None:
        assert history.list_runs() == []
        return
    record = history.list_runs()[0]
    run_id = record["id"]
    assert record["exit_code"] is None
    assert history.bound_effects(run_id, plan_to_dict(plan))[0]["state"] == expected_state

    def effect(args):
        with target.open("a") as stream:
            stream.write(args["label"] + "\n")
        return {"ok": True}

    registry = {"effect": Tool("effect", {"label": str}, {}, effect)}
    for _ in range(2):
        state = loop.run_plan("task", plan, config, registry, run_id=run_id)
        assert state.status == status
        assert state.run_id == run_id
        assert read() == after
    if status == "HALTED":
        assert len(history.load_events(run_id)) == 2
    else:
        assert "uncertain effect outcome" in format_output(state)
        assert history.load_events(run_id) == []
    assert len(history.list_runs()) == 1


@pytest.mark.parametrize("change", ["args", "order", "goal", "halt", "count", "stored_plan", "missing_effect"])
def test_recovery_rejects_binding_changes(setup, change):
    plan, registry, calls, config = setup
    raw = plan_to_dict(plan)
    run_id = history.begin_run(
        "task",
        raw,
        0,
        registry_contract_digest=history.tool_registry_contract_digest(registry),
    )
    if change == "args":
        raw["steps"][0]["args"] = {"label": "substitute"}
    elif change == "order":
        raw["steps"][:2] = reversed(raw["steps"][:2])
    elif change == "goal":
        raw["goal"] = "substitute"
    elif change == "halt":
        raw["steps"][-1]["reason"] = "substitute"
    elif change == "count":
        raw["steps"].pop(0)
    else:
        with history._conn() as conn:
            if change == "stored_plan":
                conn.execute("UPDATE runs SET plan_json=? WHERE id=?", ('{}', run_id))
            else:
                conn.execute("DELETE FROM effects WHERE run_id=? AND step=1", (run_id,))
    from apex.core.planner import parse_plan
    supplied = parse_plan(json.dumps(raw), registry)
    state = loop.run_plan("task", supplied, config, registry, run_id=run_id)
    assert state.status == "ERROR"
    assert calls == []
    assert history.load_events(run_id) == []


def test_invalid_later_step_blocks_direct_python_execution(setup):
    plan, registry, calls, config = setup
    invalid = Plan(plan.goal, (plan.steps[0], ToolCall("effect", {"label": 42}), Halt("done")))
    assert loop.run_plan("task", invalid, config, registry).status == "ERROR"
    assert calls == []
    assert not history.DB_PATH.exists()


@pytest.mark.parametrize("failure", ["exception", "output"])
def test_observed_error_does_not_mean_no_effect(setup, failure):
    plan, _, calls, config = setup

    def effect(args):
        calls.append(args["label"])
        if failure == "exception":
            raise RuntimeError("after effect")
        return {"not_json": object()}

    registry = {"effect": Tool("effect", {"label": str}, {}, effect)}
    state = loop.run_plan("task", plan, config, registry)
    row = history.bound_effects(state.run_id, plan_to_dict(plan))[0]
    assert row["state"] == "FAILED_UNKNOWN"
    assert "error" in json.loads(row["result_json"])
    assert loop.run_plan("task", plan, config, registry, run_id=state.run_id).status == "ERROR"
    assert calls == ["one"]


def test_legacy_live_blocked_dry_and_simulate_preserved(setup, monkeypatch, capsys):
    from apex.replay import replay_main
    plan, registry, calls, _ = setup
    run_id = history.record_run("task", plan_to_dict(plan), 0, 0, 0)
    monkeypatch.setattr("apex.core.toolloader.build_registry", lambda _: registry)
    for mode in ("dry", "simulate"):
        replay_main([str(run_id), "--mode", mode])
    with pytest.raises(SystemExit) as error:
        replay_main([str(run_id), "--mode", "live"])
    assert error.value.code == 1
    assert "no durable effect ledger" in capsys.readouterr().out
    assert calls == []


def test_storage_failure_prevents_dispatch(setup, monkeypatch):
    plan, registry, calls, config = setup
    monkeypatch.setattr(loop, "dispatch_effect", Mock(side_effect=OSError("disk failed")))
    with pytest.raises(OSError):
        loop.run_plan("task", plan, config, registry)
    assert calls == []


def test_outcome_storage_failure_blocks_recovery(setup, monkeypatch):
    plan, registry, calls, config = setup
    with monkeypatch.context() as patch:
        patch.setattr(loop, "observe_effect", Mock(side_effect=OSError("disk failed")))
        with pytest.raises(OSError):
            loop.run_plan("task", plan, config, registry)
    run_id = history.list_runs()[0]["id"]
    assert history.bound_effects(run_id, plan_to_dict(plan))[0]["state"] == "DISPATCHING"
    assert loop.run_plan("task", plan, config, registry, run_id=run_id).status == "ERROR"
    assert calls == ["one"]


def test_restart_during_retry_safe_delay_is_still_blocked(setup, monkeypatch):
    plan, _, calls, config = setup

    def effect(args):
        calls.append(args["label"])
        raise RuntimeError("retry-safe failure")

    registry = {"effect": Tool("effect", {"label": str}, {}, effect, retry_safe=True)}
    monkeypatch.setattr(loop, "sleep", Mock(side_effect=SystemExit(73)))
    with pytest.raises(SystemExit):
        loop.run_plan("task", plan, config, registry)
    run_id = history.list_runs()[0]["id"]
    row = history.bound_effects(run_id, plan_to_dict(plan))[0]
    assert row["state"] == "DISPATCHING"
    assert json.loads(row["result_json"]) == {"error": "retry-safe failure"}
    assert loop.run_plan("task", plan, config, registry, run_id=run_id).status == "ERROR"
    assert calls == ["one"]


def test_tool_cannot_mutate_bound_arguments(setup):
    plan, _, _, config = setup
    original = json.dumps(plan_to_dict(plan))
    def effect(args):
        args["label"] = "mutated"
        return {"ok": True}
    state = loop.run_plan("task", plan, config, {"effect": Tool("effect", {"label": str}, {}, effect)})
    assert json.dumps(history.load_run(state.run_id)["plan"]) == original
    assert json.dumps(plan_to_dict(state.plan)) == original
    assert json.dumps(plan_to_dict(plan)) == original


def test_authorization_binding_is_committed_before_dispatch(setup, monkeypatch):
    plan, registry, calls, config = setup
    approved = plan_to_dict(plan)
    authorization = {
        "authorization_id": "auth-ledger-1",
        "approved_plan_digest": history.plan_digest(approved),
        "policy_digest_or_ref": "policy-ledger",
        "authority_ref": "test-authority",
        "decision": True,
    }
    original = loop.dispatch_effect

    def dispatch(run_id, step):
        detail = history.load_run_detail(run_id)
        assert detail["authorization"] == authorization
        assert detail["ledger"]["plan_digest"] == authorization["approved_plan_digest"]
        assert len(calls) == step
        original(run_id, step)

    monkeypatch.setattr(loop, "dispatch_effect", dispatch)
    state = loop.run_plan("task", plan, config, registry, authorization=authorization)
    assert state.status == "HALTED"
    assert calls == ["one", "two"]

    # Durable authorization is sufficient for same-run recovery; it is not reissued.
    recovered = loop.run_plan("task", plan, config, registry, run_id=state.run_id)
    assert recovered.status == "HALTED"
    assert calls == ["one", "two"]


def test_authorization_mismatch_blocks_before_run_creation(setup):
    plan, registry, calls, config = setup
    authorization = {
        "authorization_id": "auth-bad",
        "approved_plan_digest": "0" * 64,
        "policy_digest_or_ref": "policy-ledger",
        "authority_ref": "test-authority",
        "decision": True,
    }
    state = loop.run_plan("task", plan, config, registry, authorization=authorization)
    assert state.status == "ERROR"
    assert calls == []
    assert history.list_runs() == []


def test_recovery_rejects_supplied_authorization_substitution(setup):
    plan, registry, calls, config = setup
    approved = plan_to_dict(plan)
    authorization = {
        "authorization_id": "auth-original",
        "approved_plan_digest": history.plan_digest(approved),
        "policy_digest_or_ref": "policy-ledger",
        "authority_ref": "test-authority",
        "decision": True,
    }
    run_id = history.begin_run(
        "task",
        approved,
        0,
        authorization=authorization,
        registry_contract_digest=history.tool_registry_contract_digest(registry),
    )
    substituted = dict(authorization, authorization_id="auth-substitute")
    state = loop.run_plan(
        "task", plan, config, registry, run_id=run_id, authorization=substituted
    )
    assert state.status == "ERROR"
    assert calls == []
    assert history.load_events(run_id) == []


def test_tool_registry_contract_digest_is_deterministic_and_contract_sensitive():
    base = {
        "effect": Tool(
            "effect", {"label": str}, {"ok": bool},
            lambda args: {"ok": True}, required=frozenset({"label"})
        )
    }
    equivalent = {
        "effect": Tool(
            "effect", {"label": str}, {"ok": bool},
            lambda args: {"ok": False}, required=frozenset({"label"})
        )
    }
    assert (
        history.tool_registry_contract_digest(base)
        == history.tool_registry_contract_digest(equivalent)
    )

    variants = [
        {"effect": Tool("effect", {"label": object}, {"ok": bool}, lambda args: {}, required=frozenset({"label"}))},
        {"effect": Tool("effect", {"label": str}, {"ok": object}, lambda args: {}, required=frozenset({"label"}))},
        {"effect": Tool("effect", {"label": str}, {"ok": bool}, lambda args: {}, required=frozenset())},
        {"effect": Tool("effect", {"label": str}, {"ok": bool}, lambda args: {}, required=frozenset({"label"}), retry_safe=True)},
    ]
    base_digest = history.tool_registry_contract_digest(base)
    assert all(history.tool_registry_contract_digest(item) != base_digest for item in variants)


def test_recovery_rejects_tool_registry_contract_change_before_dispatch(setup):
    plan, registry, calls, config = setup
    state = loop.run_plan("task", plan, config, registry)
    assert state.status == "HALTED"
    assert calls == ["one", "two"]

    changed = {
        "effect": Tool(
            "effect",
            {"label": str},
            {},
            lambda args: calls.append("changed") or {"ok": True},
            retry_safe=True,
        )
    }
    recovered = loop.run_plan("task", plan, config, changed, run_id=state.run_id)
    assert recovered.status == "ERROR"
    assert "tool registry contract digest mismatch" in format_output(recovered)
    assert calls == ["one", "two"]


def test_registry_unbound_ledger_blocks_live_recovery(setup):
    plan, registry, calls, config = setup
    run_id = history.begin_run("task", plan_to_dict(plan), 0)
    recovered = loop.run_plan("task", plan, config, registry, run_id=run_id)
    assert recovered.status == "ERROR"
    assert "tool registry contract binding is missing" in format_output(recovered)
    assert calls == []
    assert history.load_events(run_id) == []
