"""ASON adversarial harness — P2.5 gate for public release.

Categories:
  CAT1: blast_radius rejection
  CAT2: max_steps violation
  CAT3: tool allowlist enforcement
  CAT4: malformed plan (schema-level)
  CAT5: timeout elicitation (executor-level)
  CAT6: concurrent isolation
"""
from __future__ import annotations
import json
import threading
import unittest.mock as mock
import pytest
from pydantic import ValidationError
from ason.schema import ASONRequest, ApexPlan, ApexPlanStep, Policy
from ason.validator import validate
from ason.executor import ASONExecutor, _apex_plan


def _req(steps, policy=None):
    p = ApexPlan(steps=[ApexPlanStep(tool=t, args=a) for t, a in steps])
    return ASONRequest(plan=p, policy=policy or Policy())


def _fake_apex_resp(run_id=1, exit_code=0):
    resp = mock.MagicMock()
    resp.read.return_value = json.dumps({"run_id": run_id, "exit_code": exit_code}).encode()
    resp.__enter__ = lambda s: s
    resp.__exit__ = mock.MagicMock(return_value=False)
    return resp


class TestBlastRadiusRejection:
    def test_local_blocks_http_get(self):
        r = validate(_req([("http_get", {"url": "http://x"})], Policy(blast_radius="local")))
        assert not r.accepted
        assert any("blast_radius" in v for v in r.violations)

    def test_local_blocks_http_post(self):
        r = validate(_req([("http_post", {"url": "http://x", "body": "{}"})], Policy(blast_radius="local")))
        assert not r.accepted
        assert any("blast_radius" in v for v in r.violations)

    def test_none_blocks_write_file(self):
        r = validate(_req([("write_file", {"path": "/tmp/x", "content": "y"})], Policy(blast_radius="none")))
        assert not r.accepted
        assert any("blast_radius" in v for v in r.violations)

    def test_none_blocks_delete_file(self):
        r = validate(_req([("delete_file", {"path": "/tmp/x"})], Policy(blast_radius="none")))
        assert not r.accepted
        assert any("blast_radius" in v for v in r.violations)

    def test_network_permits_http(self):
        r = validate(_req([("http_get", {"url": "http://x"})], Policy(blast_radius="network")))
        assert r.accepted

    def test_network_permits_write_file(self):
        r = validate(_req([("write_file", {"path": "/tmp/x", "content": "y"})], Policy(blast_radius="network")))
        assert r.accepted

    def test_rejected_plan_never_reaches_executor(self):
        ex = ASONExecutor()
        req = _req([("http_get", {"url": "http://x"})], Policy(blast_radius="local"))
        with mock.patch("urllib.request.urlopen") as m:
            result = ex.submit(req)
        m.assert_not_called()
        assert not result["accepted"]


class TestMaxStepsViolation:
    def test_at_limit_accepted(self):
        steps = [("read_file", {"path": "/tmp/x"})] * 4
        r = validate(_req(steps, Policy(max_steps=4)))
        assert r.accepted

    def test_over_limit_rejected(self):
        steps = [("read_file", {"path": "/tmp/x"})] * 5
        r = validate(_req(steps, Policy(max_steps=4)))
        assert not r.accepted
        assert any("max_steps" in v for v in r.violations)

    def test_policy_max_steps_upper_bound(self):
        with pytest.raises(ValidationError):
            Policy(max_steps=33)

    def test_policy_max_steps_lower_bound(self):
        with pytest.raises(ValidationError):
            Policy(max_steps=0)


class TestToolAllowlist:
    def test_tool_in_allowlist_accepted(self):
        r = validate(_req([("read_file", {"path": "/tmp/x"})], Policy(allowed_tools=["read_file"])))
        assert r.accepted

    def test_tool_not_in_allowlist_rejected(self):
        r = validate(_req([("write_file", {"path": "/tmp/x", "content": "y"})], Policy(allowed_tools=["read_file"])))
        assert not r.accepted
        assert any("not in allowed_tools" in v for v in r.violations)

    def test_empty_allowlist_permits_non_blocked(self):
        r = validate(_req([("read_file", {"path": "/tmp/x"})], Policy(allowed_tools=[])))
        assert r.accepted

    def test_allowlist_does_not_override_blocked_tool(self):
        r = validate(_req([("shell", {"cmd": "ls"})], Policy(allowed_tools=["shell"])))
        assert not r.accepted
        assert any("unconditionally blocked" in v for v in r.violations)


class TestMalformedPlan:
    def test_empty_steps_accepted(self):
        r = validate(_req([]))
        assert r.accepted

    def test_missing_tool_field_raises(self):
        with pytest.raises(ValidationError):
            ApexPlanStep(args={"path": "/tmp/x"})

    def test_missing_args_field_raises(self):
        with pytest.raises(ValidationError):
            ApexPlanStep(tool="read_file")

    def test_invalid_blast_radius_raises(self):
        with pytest.raises(ValidationError):
            Policy(blast_radius="galaxy")

    def test_apex_plan_round_trips(self):
        req = _req([("read_file", {"path": "/tmp/x"})], Policy(blast_radius="network"))
        d = _apex_plan(req)
        assert d["steps"][0]["name"] == "read_file"
        assert d["steps"][-1]["type"] == "halt"


class TestTimeoutElicitation:
    def test_http_timeout_returns_error_not_exception(self):
        ex = ASONExecutor(api_key="k")
        req = _req([("read_file", {"path": "/tmp/x"})])
        with mock.patch("urllib.request.urlopen", side_effect=TimeoutError("timed out")):
            result = ex.submit(req)
        assert result["accepted"] is True
        assert "error" in result
        assert result["apex_response"] is None

    def test_http_error_returns_error_not_exception(self):
        import urllib.error
        ex = ASONExecutor(api_key="k")
        req = _req([("read_file", {"path": "/tmp/x"})])
        exc = urllib.error.HTTPError(url="http://x", code=500, msg="err", hdrs=None, fp=None)
        with mock.patch("urllib.request.urlopen", side_effect=exc):
            result = ex.submit(req)
        assert result["accepted"] is True
        assert "error" in result


class TestConcurrentIsolation:
    def test_concurrent_validates_independently(self):
        N = 20
        results = [None] * N
        policies = [
            Policy(blast_radius="local") if i % 2 == 0 else Policy(blast_radius="network")
            for i in range(N)
        ]

        def run(i):
            req = _req([("http_get", {"url": "http://x"})], policies[i])
            results[i] = validate(req)

        threads = [threading.Thread(target=run, args=(i,)) for i in range(N)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        for i, r in enumerate(results):
            if i % 2 == 0:
                assert not r.accepted, f"thread {i} should be rejected"
            else:
                assert r.accepted, f"thread {i} should be accepted"

    def test_concurrent_executor_submits_independently(self):
        N = 10
        call_count = {"n": 0}
        authorization_ids = []
        lock = threading.Lock()

        def fake_urlopen(req, timeout=None):
            body = json.loads(req.data)
            assert req.full_url == "http://127.0.0.1:8080/authorized-run"
            assert body["authorization"]["authority_ref"] == "test-concurrent"
            with lock:
                call_count["n"] += 1
                authorization_ids.append(body["authorization"]["authorization_id"])
                run_id = call_count["n"]
            return _fake_apex_resp(run_id=run_id)

        ex = ASONExecutor(api_key="k", authority_ref="test-concurrent")

        def run(_):
            req = _req([("read_file", {"path": "/tmp/x"})])
            with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
                result = ex.submit(req)
            assert result["accepted"]
            assert result["apex_response"] is not None

        threads = [threading.Thread(target=run, args=(i,)) for i in range(N)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert call_count["n"] == N
        assert len(authorization_ids) == N
        assert len(set(authorization_ids)) == N
