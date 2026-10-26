"""Demonstrate real process-crash recovery with isolated synthetic effects.

Run from a source checkout: python examples/recovery.py
Python 3.11+ on Linux/macOS; standard library only, no provider or RAG calls.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

# Resolve this checkout rather than an unrelated installed APEX version.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from apex import history
from apex.config import Config
from apex.core import loop
from apex.core.types import ErrorEvent, Halt, Plan, Tool, ToolCall, plan_to_dict

CRASH_EXIT = 73


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def context(directory, boundary, *, child=False):
    history.DB_PATH = directory / "runs.db"
    target = directory / "effects.txt"

    def effect(args):
        with target.open("a", encoding="utf-8") as stream:
            stream.write(args["label"] + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        if child and boundary == "uncertain":
            os._exit(CRASH_EXIT)
        return {"written": args["label"]}

    registry = {"append": Tool("append", {"label": str}, {"written": str}, effect)}
    plan = Plan("Record two synthetic effects", (
        ToolCall("append", {"label": "first"}),
        ToolCall("append", {"label": "second"}), Halt("complete"),
    ))
    config = Config(api_key="", provider="gemini", model="unused", db_path=directory / "memory.db",
                    trace=False, dry_run=False, full_trace=False, trace_path=None, audit=False)
    return plan, registry, config, target


def crash_child(directory, boundary):
    plan, registry, config, _ = context(directory, boundary, child=True)
    if boundary == "recorded":
        observe = loop.observe_effect

        def crash_after_commit(*args, **kwargs):
            observe(*args, **kwargs)
            os._exit(CRASH_EXIT)

        # Fault injection lives in this disposable child only.
        loop.observe_effect = crash_after_commit
    loop.run_plan(plan.goal, plan, config, registry)
    raise RuntimeError("expected crash boundary was not reached")


def demonstrate(directory, boundary):
    child = subprocess.run(
        [sys.executable, str(Path(__file__).resolve()), "--child", str(directory), boundary],
        capture_output=True, text=True, timeout=15,
    )
    require(child.returncode == CRASH_EXIT, f"unexpected child exit: {child.returncode}: {child.stderr}")
    plan, registry, config, target = context(directory, boundary)
    # Every scenario owns a new database, so the first run has ID 1.
    states = [row["state"] for row in history.bound_effects(1, plan_to_dict(plan))]
    expected = "SUCCEEDED" if boundary == "recorded" else "DISPATCHING"
    require(states == [expected, "INTENT_RECORDED"], f"unexpected ledger: {states}")
    print("Ledger after crash: " + " -> ".join(states))
    result = loop.run_plan(plan.goal, plan, config, registry, run_id=1)
    recovered = loop.run_plan(plan.goal, plan, config, registry, run_id=1)
    effects = target.read_text(encoding="utf-8").splitlines()
    if boundary == "recorded":
        require(result.status == recovered.status == "HALTED", "completed recovery failed")
        require(effects == ["first", "second"], "recovery duplicated or lost an effect")
        print("Recovery: HALTED | effects: " + ", ".join(effects))
        print("Repeat recovery: HALTED | additional effects: 0")
    else:
        for state in (result, recovered):
            require(state.status == "ERROR" and any(
                isinstance(event, ErrorEvent) and event.error_type == "RecoveryBlocked"
                for event in state.history
            ), "ambiguous recovery was not blocked")
        require(effects == ["first"], "ambiguous recovery dispatched an effect")
        print("Recovery: BLOCKED | effects: " + ", ".join(effects))
        print("Repeat recovery: BLOCKED | additional effects: 0")


def main():
    print("APEX / durable recovery demo")
    print("Real subprocess crashes. Temporary SQLite ledger. No network or API key.")
    original_path = history.DB_PATH
    try:
        with tempfile.TemporaryDirectory(prefix="apex-recovery-") as temporary:
            for boundary, title in (
                ("recorded", "1. Crash after the first result is committed"),
                ("uncertain", "2. Crash after an effect, before its result is committed"),
            ):
                directory = Path(temporary) / boundary
                directory.mkdir()
                print("\n" + title)
                demonstrate(directory, boundary)
    finally:
        history.DB_PATH = original_path
    print("\nPASS: no duplicate effects; ambiguous recovery refused.")
    print("Scope: these process-crash scenarios; not exactly-once external delivery.")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--child" and sys.argv[3] in {"recorded", "uncertain"}:
        crash_child(Path(sys.argv[2]), sys.argv[3])
    elif len(sys.argv) == 1:
        main()
    else:
        raise SystemExit("usage: python examples/recovery.py")
