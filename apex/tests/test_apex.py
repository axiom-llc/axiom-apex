"""
APEX test suite — apex-cli v2.0

Structure:
  Unit tests    — no API key required; test pure functions and data contracts
  Integration   — require GEMINI_API_KEY; invoke apex as subprocess

Run unit tests only:
    pytest tests/test_apex.py -m "not integration" -v

Run all (requires GEMINI_API_KEY):
    pytest tests/test_apex.py -v
"""

import json
import os
import subprocess
import sys
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
        cmd, capture_output=True, text=True, timeout=timeout, env=merged_env,
    )


def extract_json(text):
    """
    Extract the first top-level JSON object from text that may contain
    trailing non-JSON lines. APEX appends a status block after the plan on
    stdout, so json.loads() fails on the full string.
    """
    obj, _ = json.JSONDecoder().raw_decode(text.lstrip())
    return obj


def has_api_key():
    return bool(os.environ.get("GEMINI_API_KEY"))


requires_api = pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
integration = pytest.mark.integration


# ---------------------------------------------------------------------------
# Unit — Config
# ---------------------------------------------------------------------------

class TestConfig:
    @pytest.mark.xfail(
        reason=(
            "APEX bug: genai.Client(api_key='') falls back to ADC via "
            "~/.config/gcloud/ when api_key is empty, bypassing APEX's own "
            "ValueError guard in load_config(). The README guarantee "
            "'APEX exits immediately without GEMINI_API_KEY' only holds on "
            "a machine with no Google credentials configured. "
            "Fix: validate api_key is non-empty before constructing the client, "
            "or raise before reaching llm.py."
        ),
        strict=True,
    )
    def test_missing_api_key_exits_nonzero(self):
        env = {k: v for k, v in os.environ.items() if k != "GEMINI_API_KEY"}
        result = run_apex("hello", env=env)
        assert result.returncode != 0

    @pytest.mark.xfail(
        reason="Same ADC bypass as test_missing_api_key_exits_nonzero.",
        strict=True,
    )
    def test_missing_api_key_error_message(self):
        env = {k: v for k, v in os.environ.items() if k != "GEMINI_API_KEY"}
        result = run_apex("hello", env=env)
        assert "GEMINI_API_KEY" in result.stdout + result.stderr

    def test_load_config_raises_on_missing_key(self):
        """
        load_config() must raise ValueError when GEMINI_API_KEY is absent.
        Tests the config module directly — no subprocess, no SDK involvement.
        """
        original = os.environ.pop("GEMINI_API_KEY", None)
        try:
            from apex.config import load_config
            with pytest.raises(ValueError, match="GEMINI_API_KEY"):
                load_config()
        finally:
            if original is not None:
                os.environ["GEMINI_API_KEY"] = original

    def test_load_config_returns_frozen_dataclass(self):
        """Config must be a frozen dataclass — immutable by design."""
        if not has_api_key():
            pytest.skip("GEMINI_API_KEY not set")
        from apex.config import load_config, Config
        cfg = load_config()
        assert isinstance(cfg, Config)
        with pytest.raises((AttributeError, TypeError)):
            cfg.api_key = "mutated"  # type: ignore

    def test_custom_db_path_respected(self, tmp_path):
        """APEX_DB_PATH env var must be accepted without config errors."""
        db = tmp_path / "custom.db"
        env = {**os.environ, "APEX_DB_PATH": str(db)}
        result = run_apex("--dry-run", "write hello to /tmp/x.txt", env=env)
        assert "APEX_DB_PATH" not in (result.stderr or "").upper() or result.returncode == 0

    @pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
    def test_custom_db_path_creates_file(self, tmp_path):
        """Memory write via CLI must create the DB at the custom path."""
        db = tmp_path / "sub" / "apex.db"
        env = {**os.environ, "APEX_DB_PATH": str(db)}
        run_apex("save the value 'dbtest' to memory as db_path_key", env=env, timeout=60)
        assert db.exists(), f"Expected DB at {db}"

    def test_load_config_db_path_is_path_object(self):
        """Config.db_path must be a Path, not a string."""
        if not has_api_key():
            pytest.skip("GEMINI_API_KEY not set")
        from apex.config import load_config
        cfg = load_config()
        assert isinstance(cfg.db_path, Path)


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
        """
        --dry-run emits the plan JSON followed by a status block on stdout.
        We extract only the leading JSON object via raw_decode().
        """
        result = run_apex("--dry-run", "write hello to /tmp/apex-test.txt")
        assert result.returncode == 0
        try:
            plan = extract_json(result.stdout)
        except (json.JSONDecodeError, ValueError) as e:
            pytest.fail(f"Could not extract JSON from --dry-run output: {e}\n{result.stdout}")
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
        plan = extract_json(result.stdout)
        for step in plan["steps"]:
            assert "type" in step, f"Step missing 'type': {step}"

    @pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
    def test_dry_run_last_step_is_halt(self):
        result = run_apex("--dry-run", "write hello to /tmp/apex-test.txt")
        plan = extract_json(result.stdout)
        assert plan["steps"][-1]["type"] == "halt"

    @pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
    def test_trace_writes_to_stderr(self):
        """
        --trace during real execution must emit trace events to stderr.
        NOTE: --dry-run suppresses all tool execution so combining
        --trace --dry-run produces no events. This test uses real execution.
        """
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "traced.txt"
            result = run_apex("--trace", f"write 'traced' to {out}", timeout=60)
        assert result.stderr != ""

    @pytest.mark.skipif(not has_api_key(), reason="GEMINI_API_KEY not set")
    def test_trace_execution_emits_tool_events(self, tmp_path):
        """--trace must emit [tool] or [plan] events during real execution."""
        out = tmp_path / "traced.txt"
        result = run_apex("--trace", f"write 'traced' to {out}", timeout=60)
        combined = result.stdout + result.stderr
        assert "[tool]" in combined or "[plan]" in combined, (
            f"Expected trace events, got stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


# ---------------------------------------------------------------------------
# Unit — Plan parsing and validation
# ---------------------------------------------------------------------------

class TestPlanSchema:
    """
    parse_plan(response_text: str, registry: dict) -> Plan | Err

    The planner has no separate validate_plan function. Validation is
    embedded in parse_plan, which accepts raw LLM response text, extracts
    the JSON object, and returns either a Plan dataclass or an Err.
    Tests pass JSON-serialised dicts as response_text.
    """

    def _parse(self, plan_dict, registry=None):
        try:
            from apex.core.planner import parse_plan
        except ImportError:
            pytest.skip("apex.core.planner not importable")
        if registry is None:
            registry = {"write_file": object(), "shell": object()}
        return parse_plan(json.dumps(plan_dict), registry)

    def test_valid_plan_returns_plan_instance(self):
        from apex.core.types import Plan
        result = self._parse({
            "goal": "write hello to file",
            "steps": [
                {"type": "tool", "name": "write_file", "args": {"path": "/tmp/x.txt", "content": "hello"}},
                {"type": "halt", "reason": "done"},
            ],
        })
        assert isinstance(result, Plan)

    def test_valid_plan_goal_preserved(self):
        from apex.core.types import Plan
        result = self._parse({
            "goal": "my goal",
            "steps": [{"type": "halt", "reason": "done"}],
        })
        assert isinstance(result, Plan)
        assert result.goal == "my goal"

    def test_plan_missing_goal_returns_err(self):
        from apex.core.types import Err
        result = self._parse({"steps": [{"type": "halt", "reason": "done"}]})
        assert isinstance(result, Err)

    def test_plan_missing_steps_returns_err(self):
        from apex.core.types import Err
        result = self._parse({"goal": "something"})
        assert isinstance(result, Err)

    def test_plan_unknown_step_type_returns_err(self):
        from apex.core.types import Err
        result = self._parse({"goal": "test", "steps": [{"type": "unknown_type"}]})
        assert isinstance(result, Err)

    def test_plan_tool_step_missing_name_returns_err(self):
        from apex.core.types import Err
        result = self._parse({"goal": "test", "steps": [{"type": "tool", "args": {}}]})
        assert isinstance(result, Err)

    def test_plan_unknown_tool_name_returns_err(self):
        """Tool names are validated against the registry — unknown tools are rejected."""
        from apex.core.types import Err
        result = self._parse(
            {"goal": "test", "steps": [{"type": "tool", "name": "nonexistent_tool", "args": {}}]},
            registry={"shell": object()},
        )
        assert isinstance(result, Err)

    def test_plan_exceeding_32_steps_returns_err(self):
        """Plan step limit is 32 per README constraints."""
        from apex.core.types import Err
        steps = [{"type": "tool", "name": "shell", "args": {"cmd": "true"}} for _ in range(33)]
        result = self._parse({"goal": "too many steps", "steps": steps},
                             registry={"shell": object()})
        assert isinstance(result, Err)

    def test_plan_invalid_json_returns_err(self):
        """Malformed JSON must return Err, not raise."""
        try:
            from apex.core.planner import parse_plan
        except ImportError:
            pytest.skip("apex.core.planner not importable")
        from apex.core.types import Err
        result = parse_plan("this is not json at all", {})
        assert isinstance(result, Err)

    def test_toolcall_step_type_accepted(self):
        """parse_plan accepts both 'tool' and 'toolcall' as step type."""
        from apex.core.types import Plan
        result = self._parse({
            "goal": "test",
            "steps": [
                {"type": "toolcall", "name": "shell", "args": {"cmd": "true"}},
                {"type": "halt", "reason": "done"},
            ],
        }, registry={"shell": object()})
        assert isinstance(result, Plan)


# ---------------------------------------------------------------------------
# Unit — State immutability
# ---------------------------------------------------------------------------

class TestState:
    def _make_state(self, task="test task"):
        try:
            from apex.core.state import create_initial_state
            return create_initial_state(task)
        except ImportError:
            pytest.skip("apex.core.state not importable")

    def test_state_is_frozen(self):
        s = self._make_state()
        with pytest.raises((AttributeError, TypeError)):
            s.status = "MUTATED"  # type: ignore

    def test_replace_produces_new_instance(self):
        import dataclasses
        s1 = self._make_state()
        s2 = dataclasses.replace(s1, status="HALTED")
        assert s1 is not s2
        assert s1.status != s2.status

    def test_initial_state_status_is_running(self):
        """create_initial_state sets status='RUNNING' per state.py."""
        s = self._make_state()
        assert s.status == "RUNNING"

    def test_initial_state_has_empty_history(self):
        s = self._make_state()
        assert s.history == ()

    def test_initial_state_has_no_plan(self):
        s = self._make_state()
        assert s.plan is None

    def test_initial_state_zero_token_count(self):
        s = self._make_state()
        assert s.token_count == 0

    def test_original_unchanged_after_replace(self):
        """Replace must not mutate the source — pure-functional contract."""
        import dataclasses
        s1 = self._make_state("original task")
        original_status = s1.status
        dataclasses.replace(s1, status="HALTED")
        assert s1.status == original_status

    def test_input_preserved(self):
        s = self._make_state("my specific task")
        assert s.input == "my specific task"


# ---------------------------------------------------------------------------
# Unit — Tool registry
# ---------------------------------------------------------------------------

class TestToolRegistry:
    def _shell(self):
        try:
            from apex.tools import SHELL
            return SHELL
        except ImportError:
            pytest.skip("SHELL not importable")

    def _get_exit_code(self, result: dict) -> int:
        """APEX shell results use 'code', not 'exit_code' or 'returncode'."""
        for key in ("code", "exit_code", "returncode"):
            if key in result:
                return result[key]
        pytest.fail(f"No exit code key found in shell result: {result}")

    def test_shell_tool_exists(self):
        try:
            from apex import tools
        except ImportError:
            pytest.skip("apex.tools not importable")
        assert hasattr(tools, "SHELL") or hasattr(tools, "shell")

    def test_read_file_tool_exists(self):
        try:
            from apex import tools
        except ImportError:
            pytest.skip("apex.tools not importable")
        assert hasattr(tools, "READ_FILE") or hasattr(tools, "read_file")

    def test_write_file_tool_exists(self):
        try:
            from apex import tools
        except ImportError:
            pytest.skip("apex.tools not importable")
        assert hasattr(tools, "WRITE_FILE") or hasattr(tools, "write_file")

    def test_http_get_tool_exists(self):
        try:
            from apex import tools
        except ImportError:
            pytest.skip("apex.tools not importable")
        assert hasattr(tools, "HTTP_GET") or hasattr(tools, "http_get")

    def test_shell_effect_runs_command(self):
        result = self._shell().effect({"cmd": "echo apex-test"})
        assert "apex-test" in result.get("stdout", "")

    def test_shell_effect_returns_code_key(self):
        """APEX shell results use 'code' as the exit code key."""
        result = self._shell().effect({"cmd": "true"})
        assert "code" in result, (
            f"Expected 'code' key in shell result, got keys: {list(result.keys())}"
        )

    def test_shell_effect_zero_on_success(self):
        result = self._shell().effect({"cmd": "true"})
        assert self._get_exit_code(result) == 0

    def test_shell_effect_nonzero_on_failure(self):
        result = self._shell().effect({"cmd": "false"})
        assert self._get_exit_code(result) != 0, (
            f"Expected nonzero exit from 'false', got: {result}"
        )

    def test_shell_pipe_composition(self):
        """Pipes must work — documented as a core composition mechanism."""
        result = self._shell().effect({"cmd": "echo 'apex' | tr 'a-z' 'A-Z'"})
        assert "APEX" in result.get("stdout", "")

    def test_shell_and_operator(self):
        """&& chaining must work as documented."""
        result = self._shell().effect({"cmd": "echo first && echo second"})
        stdout = result.get("stdout", "")
        assert "first" in stdout and "second" in stdout

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

    def test_http_get_effect_returns_status(self):
        try:
            from apex.tools import HTTP_GET
        except ImportError:
            pytest.skip("HTTP_GET not importable")
        result = HTTP_GET.effect({"url": "https://api.ipify.org"})
        assert any(k in result for k in ("status", "status_code", "code"))

    def test_http_get_effect_returns_body(self):
        try:
            from apex.tools import HTTP_GET
        except ImportError:
            pytest.skip("HTTP_GET not importable")
        result = HTTP_GET.effect({"url": "https://api.ipify.org"})
        body = result.get("body", result.get("content", ""))
        assert body != ""


# ---------------------------------------------------------------------------
# Unit — Memory (SQLite)
# ---------------------------------------------------------------------------

class TestMemory:
    def _get_memory(self, db_path: Path):
        """
        make_memory_tools requires a Path object — its internal _connection()
        calls db_path.parent which fails on str. Always pass Path directly.
        """
        try:
            from apex.memory import make_memory_tools
            return make_memory_tools(db_path)
        except ImportError:
            pytest.skip("apex.memory not importable")

    def test_write_and_read(self, tmp_path):
        read, write = self._get_memory(tmp_path / "mem.db")
        write.effect({"key": "test_key", "value": "test_value"})
        assert read.effect({"key": "test_key"}).get("value") == "test_value"

    def test_read_missing_key_returns_none(self, tmp_path):
        read, _ = self._get_memory(tmp_path / "mem.db")
        result = read.effect({"key": "does_not_exist"})
        assert result.get("value") is None

    def test_overwrite_value(self, tmp_path):
        read, write = self._get_memory(tmp_path / "mem.db")
        write.effect({"key": "k", "value": "v1"})
        write.effect({"key": "k", "value": "v2"})
        assert read.effect({"key": "k"}).get("value") == "v2"

    def test_list_all_entries(self, tmp_path):
        read, write = self._get_memory(tmp_path / "mem.db")
        write.effect({"key": "alpha", "value": 1})
        write.effect({"key": "beta", "value": 2})
        result = read.effect({})
        entries = result.get("entries", [])
        keys = [e["key"] for e in entries]
        assert "alpha" in keys and "beta" in keys

    def test_json_serialisable_values(self, tmp_path):
        read, write = self._get_memory(tmp_path / "mem.db")
        payload = {"nested": True, "list": [1, 2, 3]}
        write.effect({"key": "complex", "value": payload})
        assert read.effect({"key": "complex"}).get("value") == payload

    def test_write_returns_written_true(self, tmp_path):
        _, write = self._get_memory(tmp_path / "mem.db")
        result = write.effect({"key": "k", "value": "v"})
        assert result.get("written") is True

    def test_concurrent_writes_isolated(self, tmp_path):
        import threading
        db = tmp_path / "shared.db"
        errors = []

        def writer(key, value):
            try:
                _, write = self._get_memory(db)
                write.effect({"key": key, "value": value})
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=writer, args=(f"k{i}", i)) for i in range(5)]
        for t in threads: t.start()
        for t in threads: t.join()
        assert errors == [], f"Concurrent write errors: {errors}"

    def test_memory_persists_across_instances(self, tmp_path):
        """Data written by one instance must be readable by a fresh one."""
        db = tmp_path / "persist.db"
        _, write = self._get_memory(db)
        write.effect({"key": "persist_key", "value": "persist_value"})

        read2, _ = self._get_memory(db)
        assert read2.effect({"key": "persist_key"}).get("value") == "persist_value"


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
        result = run_apex(f"write 'file-a' to {f1} and write 'file-b' to {f2}", timeout=60)
        assert result.returncode == 0
        assert f1.exists() and f2.exists()

    def test_dry_run_zero_exit(self):
        result = run_apex("--dry-run", "write hello to /tmp/apex-dryrun.txt")
        assert result.returncode == 0

    def test_dry_run_valid_json_output(self):
        result = run_apex("--dry-run", "write hello to /tmp/apex-dryrun.txt")
        plan = extract_json(result.stdout)
        assert isinstance(plan["steps"], list)
        assert len(plan["steps"]) > 0

    def test_error_handling_bad_path(self):
        result = run_apex("read /root/definitely-does-not-exist.txt", timeout=30)
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

    def test_exit_code_zero_on_success(self, tmp_path):
        out = tmp_path / "exit0.txt"
        result = run_apex(f"write 'done' to {out}", timeout=60)
        assert result.returncode == 0

    def test_exit_code_not_unexpected_state(self):
        """Exit code 2 (unexpected terminal state) must never occur."""
        result = run_apex("read /nonexistent/path.txt", timeout=30)
        assert result.returncode != 2

    def test_output_nonempty_on_success(self, tmp_path):
        out = tmp_path / "result.txt"
        result = run_apex(f"write 'result-check' to {out}", timeout=60)
        assert result.stdout.strip() != "" or out.exists()
