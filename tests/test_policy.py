from __future__ import annotations
"""Tests for ASON validator."""
import pytest
from ason.schema import ASONRequest, ASONResult, ApexPlan, ApexPlanStep, Policy
from ason.validator import validate


def _req(steps, policy=None):
    p = ApexPlan(steps=[ApexPlanStep(tool=t, args=a) for t, a in steps])
    return ASONRequest(plan=p, policy=policy or Policy())


def test_accept_valid():
    r = validate(_req([("read_file", {"path": "/tmp/x"})]))
    assert r.accepted


def test_reject_exceeds_max_steps():
    steps = [("read_file", {"path": "/tmp/x"})] * 5
    r = validate(_req(steps, Policy(max_steps=2)))
    assert not r.accepted
    assert any("max_steps" in v for v in r.violations)


def test_reject_blocked_tool():
    r = validate(_req([("shell", {"cmd": "ls"})]))
    assert not r.accepted
    assert any("unconditionally blocked" in v for v in r.violations)


def test_reject_tool_not_in_allowed():
    r = validate(_req([("http_get", {"url": "http://x"})], Policy(allowed_tools=["read_file"])))
    assert not r.accepted
    assert any("not in allowed_tools" in v for v in r.violations)


def test_empty_allowed_tools_permits_all_non_blocked():
    r = validate(_req([("http_get", {"url": "http://x"})], Policy(allowed_tools=[], blast_radius="network")))
    assert r.accepted
"""Tests for ASON rollback handler."""
import json
import sqlite3
import tempfile
from pathlib import Path
import pytest
from ason.schema import Policy
from ason.rollback import generate_rollback


def _make_db(events: list[tuple]) -> Path:
    """Create a temp runs.db with given (run_id, step, tool, args_json) rows."""
    tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    path = Path(tmp.name)
    with sqlite3.connect(path) as conn:
        conn.execute(
            "CREATE TABLE events (id INTEGER PRIMARY KEY, run_id TEXT, step INTEGER, tool TEXT, args_json TEXT)"
        )
        conn.executemany(
            "INSERT INTO events (run_id, step, tool, args_json) VALUES (?,?,?,?)",
            events,
        )
    return path


def test_no_db_returns_none(tmp_path):
    assert generate_rollback("run-1", db_path=tmp_path / "nonexistent.db") is None


def test_unknown_run_id_returns_none():
    db = _make_db([("run-1", 0, "read_file", json.dumps({"path": "/tmp/x"}))])
    assert generate_rollback("run-99", db_path=db) is None


def test_no_reversible_steps_returns_none():
    db = _make_db([("run-1", 0, "read_file", json.dumps({"path": "/tmp/x"}))])
    assert generate_rollback("run-1", db_path=db) is None


def test_write_file_generates_delete():
    db = _make_db([("run-1", 0, "write_file", json.dumps({"path": "/tmp/out.txt"}))])
    req = generate_rollback("run-1", db_path=db)
    assert req is not None
    assert len(req.plan.steps) == 1
    step = req.plan.steps[0]
    assert step.tool == "delete_file"
    assert step.args["path"] == "/tmp/out.txt"


def test_rollback_policy():
    db = _make_db([("run-1", 0, "write_file", json.dumps({"path": "/tmp/f"}))])
    req = generate_rollback("run-1", db_path=db)
    assert req.policy.blast_radius == "local"
    assert req.policy.rollback_on_failure is False


def test_steps_reversed_order():
    db = _make_db([
        ("run-1", 0, "write_file", json.dumps({"path": "/tmp/a"})),
        ("run-1", 1, "write_file", json.dumps({"path": "/tmp/b"})),
    ])
    req = generate_rollback("run-1", db_path=db)
    paths = [s.args["path"] for s in req.plan.steps]
    assert paths == ["/tmp/b", "/tmp/a"]


def test_write_file_missing_path_skipped(capsys):
    db = _make_db([("run-1", 0, "write_file", json.dumps({}))])
    req = generate_rollback("run-1", db_path=db)
    assert req is None
    assert "skipped" in capsys.readouterr().err


def test_shell_step_flagged_not_reversed(capsys):
    db = _make_db([("run-1", 0, "shell", json.dumps({"cmd": "rm -rf /tmp/x"}))])
    req = generate_rollback("run-1", db_path=db)
    assert req is None
    assert "manual review" in capsys.readouterr().err
"""ASON adversarial harness — P2.5 gate for public release.

Categories:
  CAT1: blast_radius rejection
  CAT2: max_steps violation
  CAT3: tool allowlist enforcement
  CAT4: malformed plan (schema-level)
  CAT5: timeout elicitation (executor-level)
  CAT6: concurrent isolation
"""
import json
import threading
import unittest.mock as mock
import pytest
from pydantic import ValidationError
from ason.schema import ASONRequest, ApexPlan, ApexPlanStep, Policy
from ason.validator import validate
from ason.executor import ASONExecutor, _plan_to_task


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

    def test_plan_to_task_round_trips(self):
        req = _req([("read_file", {"path": "/tmp/x"})], Policy(blast_radius="network"))
        d = json.loads(_plan_to_task(req))
        assert d["ason_plan"][0]["tool"] == "read_file"
        assert d["ason_policy"]["blast_radius"] == "network"


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
        lock = threading.Lock()

        def fake_urlopen(req, timeout=None):
            with lock:
                call_count["n"] += 1
            return _fake_apex_resp(run_id=call_count["n"])

        ex = ASONExecutor(api_key="k")

        def run(_):
            req = _req([("read_file", {"path": "/tmp/x"})])
            with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
                ex.submit(req)

        threads = [threading.Thread(target=run, args=(i,)) for i in range(N)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert call_count["n"] == N
