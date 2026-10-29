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
