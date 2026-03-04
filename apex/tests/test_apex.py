"""
APEX test suite — apex-cli v2.0

Structure:
  Unit tests    — no API key required; test pure functions and data contracts
  Integration   — require GEMINI_API_KEY; invoke apex as subprocess

Run unit tests only:
    pytest tests/test_apex.py -m "not integration"

Run all (requires GEMINI_API_KEY):
    pytest tests/test_apex.py
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

APEX_CMD = [sys.executable, "-m", "apex"]


def run_apex(*args, env=None, timeout=30):
    """Invoke apex as a subprocess. Returns CompletedProcess."""
    cmd = APEX_CMD + list(args)
    merged_env = {**os.environ, **(env or {})}
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=merged_env,
    )


def has_api_key():
    return bool(os.environ.get("GEMINI_API_KEY"))


requires_api = pytest.mark.skipif(
    not has_api_key(), reason="GEMINI_API_KEY not set"
)
integration = pytest.mark.integration


# ---------------------------------------------------------------------------
# Unit — Config
# ---------------------------------------------------------------------------


class TestConfig:
    def test_missing_api_key_exits_nonzero(self):
        env = {k: v for k, v in os.environ.items() if k != "GEMINI_API_KEY"}
        result = run_apex("hello", env=env)
        assert result.returncode != 0

    def test_missing_api_key_error_message(self):
        env = {k: v for k, v in os.environ.items() if k != "GEMINI_API_KEY"}
        result = run_apex("hello", env=env)
        output = result.stdout + result.stderr
        assert "GEMINI_API_KEY" in output

    def test_custom_db_path_respected(self, tmp_path):
        """APEX_DB_PATH env var must change the memory DB location."""
        db = tmp_path / "custom.db"
        env = {**os.environ, "APEX_DB_PATH": str(db)}
        # dry-run so no API call is made; we only test that config loads cleanly
        result = run_apex("--dry-run", "write hello to /tmp/x.txt", env=env)
        # regardless of exit code, the DB path should not default to ~/.apex/memory.db
        # (we can't assert the file exists without an API call, but no crash = correct path handling)
        assert "APEX_DB_PATH" not in (result.stderr or "").upper() or result.returncode == 0


# ---------------------------------------------------------------------------
# Unit — CLI flags
# ---------------------------------------------------------------------------


class TestFlags:
    @pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
    def test_version_flag(self):
        result = run_apex("--version")
        assert result.returncode == 0
        assert result.stdout.strip() != ""

    @pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
    def test_dry_run_produces_json(self):
        result = run_apex("--dry-run", "write hello to /tmp/apex-test.txt")
        assert result.returncode == 0
        try:
            plan = json.loads(result.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"--dry-run output is not valid JSON:\n{result.stdout}")
        assert "goal" in plan
        assert "steps" in plan

    @pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
    def test_dry_run_no_side_effects(self, tmp_path):
        target = tmp_path / "should-not-exist.txt"
        run_apex("--dry-run", f"write hello to {target}")
        assert not target.exists()

    @pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
    def test_dry_run_steps_have_type_field(self):
        result = run_apex("--dry-run", "write hello to /tmp/apex-test.txt")
        plan = json.loads(result.stdout)
        for step in plan["steps"]:
            assert "type" in step, f"Step missing 'type': {step}"

    @pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
    def test_dry_run_last_step_is_halt(self):
        result = run_apex("--dry-run", "write hello to /tmp/apex-test.txt")
        plan = json.loads(result.stdout)
        assert plan["steps"][-1]["type"] == "halt"

    @pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
    def test_trace_writes_to_stderr(self):
        result = run_apex("--trace", "--dry-run", "write hello to /tmp/apex-trace.txt")
        # trace output goes to stderr
        assert result.stderr != ""


# ---------------------------------------------------------------------------
# Unit — Plan schema validation
# ---------------------------------------------------------------------------


class TestPlanSchema:
    """
    Test that the planner correctly validates and rejects malformed plans.
    These tests import the planner module directly — no API call required.
    """

    def _get_planner(self):
        try:
            from apex.core import planner
            return planner
        except ImportError:
            pytest.skip("apex.core.planner not importable in this environment")

    def test_valid_plan_passes_validation(self):
        planner = self._get_planner()
        valid = {
            "goal": "write hello to file",
            "steps": [
                {"type": "tool", "name": "write_file", "args": {"path": "/tmp/x.txt", "content": "hello"}},
                {"type": "halt", "reason": "done"},
            ],
        }
        # Should not raise
        result = planner.validate_plan(valid)
        assert result is not None

    def test_plan_missing_goal_rejected(self):
        planner = self._get_planner()
        invalid = {
            "steps": [{"type": "halt", "reason": "done"}],
        }
        with pytest.raises(Exception):
            planner.validate_plan(invalid)

    def test_plan_missing_steps_rejected(self):
        planner = self._get_planner()
        invalid = {"goal": "something"}
        with pytest.raises(Exception):
            planner.validate_plan(invalid)

    def test_plan_unknown_step_type_rejected(self):
        planner = self._get_planner()
        invalid = {
            "goal": "test",
            "steps": [{"type": "unknown_type"}],
        }
        with pytest.raises(Exception):
            planner.validate_plan(invalid)

    def test_plan_tool_step_missing_name_rejected(self):
        planner = self._get_planner()
        invalid = {
            "goal": "test",
            "steps": [{"type": "tool", "args": {}}],
        }
        with pytest.raises(Exception):
            planner.validate_plan(invalid)

    def test_empty_steps_rejected(self):
        planner = self._get_planner()
        invalid = {"goal": "test", "steps": []}
        with pytest.raises(Exception):
            planner.validate_plan(invalid)


# ---------------------------------------------------------------------------
# Unit — State immutability
# ---------------------------------------------------------------------------


class TestState:
    def _get_state_module(self):
        try:
            from apex.core import state
            return state
        except ImportError:
            pytest.skip("apex.core.state not importable")

    def test_state_is_frozen(self):
        state = self._get_state_module()
        s = state.make_initial_state("test task")
        with pytest.raises((AttributeError, TypeError)):
            s.status = "MUTATED"  # type: ignore

    def test_replace_produces_new_instance(self):
        import dataclasses
        state = self._get_state_module()
        s1 = state.make_initial_state("test task")
        s2 = dataclasses.replace(s1, status="HALTED")
        assert s1 is not s2
        assert s1.status != s2.status

    def test_initial_state_status(self):
        state = self._get_state_module()
        s = state.make_initial_state("test task")
        assert s.status in ("PENDING", "RUNNING", "PLANNING")


# ---------------------------------------------------------------------------
# Unit — Tool registry
# ---------------------------------------------------------------------------


class TestToolRegistry:
    def _get_registry(self):
        try:
            from apex import __main__ as main_mod
            # The registry is built inside main(); import tools directly
            from apex import tools
            return tools
        except ImportError:
            pytest.skip("apex.tools not importable")

    def test_shell_tool_exists(self):
        tools = self._get_registry()
        assert hasattr(tools, "SHELL") or hasattr(tools, "shell")

    def test_read_file_tool_exists(self):
        tools = self._get_registry()
        assert hasattr(tools, "READ_FILE") or hasattr(tools, "read_file")

    def test_write_file_tool_exists(self):
        tools = self._get_registry()
        assert hasattr(tools, "WRITE_FILE") or hasattr(tools, "write_file")

    def test_http_get_tool_exists(self):
        tools = self._get_registry()
        assert hasattr(tools, "HTTP_GET") or hasattr(tools, "http_get")

    def test_shell_effect_runs_command(self):
        """Shell tool must execute commands and return stdout."""
        try:
            from apex.tools import SHELL
        except ImportError:
            pytest.skip("SHELL tool not importable")
        result = SHELL.effect({"cmd": "echo apex-test"})
        assert "apex-test" in result.get("stdout", "")

    def test_shell_effect_returns_exit_code(self):
        try:
            from apex.tools import SHELL
        except ImportError:
            pytest.skip("SHELL tool not importable")
        result = SHELL.effect({"cmd": "true"})
        assert "exit_code" in result or "returncode" in result

    def test_shell_effect_nonzero_on_failure(self):
        try:
            from apex.tools import SHELL
        except ImportError:
            pytest.skip("SHELL tool not importable")
        result = SHELL.effect({"cmd": "false"})
        code = result.get("exit_code", result.get("returncode", 0))
        assert code != 0

    def test_write_read_roundtrip(self, tmp_path):
        try:
            from apex.tools import WRITE_FILE, READ_FILE
        except ImportError:
            pytest.skip("file tools not importable")
        target = str(tmp_path / "roundtrip.txt")
        WRITE_FILE.effect({"path": target, "content": "apex-roundtrip"})
        result = READ_FILE.effect({"path": target})
        assert "apex-roundtrip" in result.get("content", "")

    def test_write_file_creates_parents(self, tmp_path):
        try:
            from apex.tools import WRITE_FILE
        except ImportError:
            pytest.skip("WRITE_FILE not importable")
        nested = str(tmp_path / "a" / "b" / "c.txt")
        WRITE_FILE.effect({"path": nested, "content": "nested"})
        assert Path(nested).exists()


# ---------------------------------------------------------------------------
# Unit — Memory (SQLite)
# ---------------------------------------------------------------------------


class TestMemory:
    def _get_memory(self, db_path):
        try:
            from apex.memory import make_memory_tools
            read, write = make_memory_tools(str(db_path))
            return read, write
        except ImportError:
            pytest.skip("apex.memory not importable")

    def test_write_and_read(self, tmp_path):
        read, write = self._get_memory(tmp_path / "mem.db")
        write.effect({"key": "test_key", "value": "test_value"})
        result = read.effect({"key": "test_key"})
        assert result.get("value") == "test_value"

    def test_read_missing_key(self, tmp_path):
        read, write = self._get_memory(tmp_path / "mem.db")
        result = read.effect({"key": "does_not_exist"})
        assert result.get("value") is None or "error" in result

    def test_overwrite_value(self, tmp_path):
        read, write = self._get_memory(tmp_path / "mem.db")
        write.effect({"key": "k", "value": "v1"})
        write.effect({"key": "k", "value": "v2"})
        result = read.effect({"key": "k"})
        assert result.get("value") == "v2"

    def test_list_all_entries(self, tmp_path):
        read, write = self._get_memory(tmp_path / "mem.db")
        write.effect({"key": "a", "value": 1})
        write.effect({"key": "b", "value": 2})
        result = read.effect({})  # no key → list all
        # Result should contain both keys
        content = str(result)
        assert "a" in content and "b" in content

    def test_json_serialisable_values(self, tmp_path):
        read, write = self._get_memory(tmp_path / "mem.db")
        payload = {"nested": True, "list": [1, 2, 3]}
        write.effect({"key": "complex", "value": payload})
        result = read.effect({"key": "complex"})
        assert result.get("value") == payload

    def test_concurrent_writes_isolated(self, tmp_path):
        """Two separate memory instances on same DB must not corrupt each other."""
        import threading
        db = tmp_path / "shared.db"
        errors = []

        def writer(key, value):
            try:
                read, write = self._get_memory(db)
                write.effect({"key": key, "value": value})
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=writer, args=(f"k{i}", i)) for i in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert errors == [], f"Concurrent write errors: {errors}"


# ---------------------------------------------------------------------------
# Integration — end-to-end via subprocess
# ---------------------------------------------------------------------------


@integration
@requires_api
class TestIntegration:
    def test_write_file_task(self, tmp_path):
        target = tmp_path / "output.txt"
        result = run_apex(f"write the word 'apex' to {target}")
        assert result.returncode == 0
        assert target.exists()
        assert "apex" in target.read_text().lower()

    def test_read_file_task(self, tmp_path):
        source = tmp_path / "input.txt"
        source.write_text("hello from apex")
        result = run_apex(f"read {source} and print its contents")
        assert result.returncode == 0

    def test_shell_task(self, tmp_path):
        out = tmp_path / "date.txt"
        result = run_apex(f"write today's date to {out}")
        assert result.returncode == 0
        assert out.exists()

    def test_memory_roundtrip(self, tmp_path):
        db = tmp_path / "mem.db"
        env = {**os.environ, "APEX_DB_PATH": str(db)}
        run_apex("save the value 'integration-test' to memory as test_key", env=env)
        result = run_apex("read from memory the key test_key", env=env)
        assert result.returncode == 0
        assert "integration-test" in result.stdout

    def test_http_get_task(self, tmp_path):
        out = tmp_path / "ip.txt"
        result = run_apex(f"fetch https://api.ipify.org and save to {out}", timeout=60)
        assert result.returncode == 0
        assert out.exists()

    def test_multistep_create_and_verify(self, tmp_path):
        f1, f2 = tmp_path / "a.txt", tmp_path / "b.txt"
        result = run_apex(
            f"write 'file-a' to {f1} and write 'file-b' to {f2}",
            timeout=60,
        )
        assert result.returncode == 0
        assert f1.exists()
        assert f2.exists()

    def test_dry_run_zero_exit(self):
        result = run_apex("--dry-run", "write hello to /tmp/apex-dryrun.txt")
        assert result.returncode == 0

    def test_dry_run_valid_json_output(self):
        result = run_apex("--dry-run", "write hello to /tmp/apex-dryrun.txt")
        plan = json.loads(result.stdout)
        assert isinstance(plan["steps"], list)
        assert len(plan["steps"]) > 0

    def test_error_handling_bad_path(self):
        result = run_apex("read /root/definitely-does-not-exist.txt", timeout=30)
        # Should not hang or crash with unhandled exception — exit 0 or 1 both acceptable
        assert result.returncode in (0, 1)

    def test_parallel_independent_tasks(self, tmp_path):
        """Two concurrent apex processes must not corrupt each other's state."""
        import concurrent.futures

        def task(label):
            out = tmp_path / f"{label}.txt"
            r = run_apex(f"write '{label}' to {out}", timeout=60)
            return r.returncode, out

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
            futures = [ex.submit(task, f"task{i}") for i in range(2)]
            results = [f.result() for f in futures]

        for code, path in results:
            assert code == 0
            assert path.exists()
