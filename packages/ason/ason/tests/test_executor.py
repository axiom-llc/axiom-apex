"""Tests for ASON executor — offline (no apex serve required)."""
import json
import unittest.mock as mock

from ason.schema import ASONRequest, ApexPlan, ApexPlanStep, Policy
from ason.executor import ASONExecutor, _apex_plan, _canonical_digest


def _req(steps, policy=None):
    p = ApexPlan(steps=[ApexPlanStep(tool=t, args=a) for t, a in steps])
    return ASONRequest(plan=p, policy=policy or Policy())


def test_rejected_plan_never_submits():
    ex = ASONExecutor()
    req = _req([("shell", {"cmd": "ls"})])
    with mock.patch("urllib.request.urlopen") as m:
        result = ex.submit(req)
    m.assert_not_called()
    assert not result["accepted"]


def test_missing_authority_blocks_before_http():
    ex = ASONExecutor()
    req = _req([("read_file", {"path": "/tmp/x"})])
    with mock.patch("urllib.request.urlopen") as m:
        result = ex.submit(req)
    m.assert_not_called()
    assert result["accepted"]
    assert result["apex_response"] is None
    assert "authority_ref" in result["error"]


def test_accepted_plan_submits_bound_authorization():
    ex = ASONExecutor(api_key="test-key", authority_ref="test-authority")
    req = _req([("read_file", {"path": "/tmp/x"})])
    fake_resp = mock.MagicMock()
    fake_resp.read.return_value = json.dumps({"run_id": 1, "exit_code": 0}).encode()
    fake_resp.__enter__ = lambda s: s
    fake_resp.__exit__ = mock.MagicMock(return_value=False)
    with mock.patch("ason.executor.uuid4", return_value="authorization-1"),             mock.patch("urllib.request.urlopen", return_value=fake_resp) as request:
        result = ex.submit(req)
    assert result["accepted"]
    assert result["apex_response"]["run_id"] == 1
    submitted = request.call_args.args[0]
    assert submitted.full_url == "http://127.0.0.1:8080/authorized-run"
    body = json.loads(submitted.data)
    assert body["plan"] == _apex_plan(req)
    assert body["authorization"] == result["authorization"]
    assert body["authorization"] == {
        "authorization_id": "authorization-1",
        "approved_plan_digest": _canonical_digest(body["plan"]),
        "policy_digest_or_ref": _canonical_digest(req.policy.model_dump(mode="json")),
        "authority_ref": "test-authority",
        "decision": True,
    }


def test_submit_authority_override():
    ex = ASONExecutor(authority_ref="default")
    req = _req([("read_file", {"path": "/tmp/x"})])
    fake_resp = mock.MagicMock()
    fake_resp.read.return_value = json.dumps({"run_id": 1, "exit_code": 0}).encode()
    fake_resp.__enter__ = lambda s: s
    fake_resp.__exit__ = mock.MagicMock(return_value=False)
    with mock.patch("urllib.request.urlopen", return_value=fake_resp):
        result = ex.submit(req, authority_ref="attempt:42")
    assert result["authorization"]["authority_ref"] == "attempt:42"


def test_apex_plan_serializes():
    req = _req([("read_file", {"path": "/tmp/x"})])
    d = _apex_plan(req)
    assert d["steps"][0]["name"] == "read_file"
    assert d["steps"][-1]["type"] == "halt"
