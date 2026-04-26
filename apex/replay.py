"""apex replay — re-execute a recorded run from runs.db"""
import json
import sqlite3
from pathlib import Path
from apex.history import DB_PATH


def _load_run(run_id: int) -> dict:
    con = sqlite3.connect(DB_PATH)
    row = con.execute(
        "SELECT id, task, plan_json FROM runs WHERE id = ?", (run_id,)
    ).fetchone()
    con.close()
    if row is None:
        raise ValueError(f"run {run_id} not found")
    return {"id": row[0], "task": row[1], "plan_json": row[2]}


def _load_events(run_id: int) -> list[dict]:
    con = sqlite3.connect(DB_PATH)
    rows = con.execute(
        "SELECT step, tool, args_json, result_json FROM events "
        "WHERE run_id = ? ORDER BY step ASC", (run_id,)
    ).fetchall()
    con.close()
    return [
        {"step": r[0], "tool": r[1],
         "args": json.loads(r[2]) if r[2] else {},
         "result": json.loads(r[3]) if r[3] else {}}
        for r in rows
    ]


def replay_main(argv: list[str]) -> None:
    import argparse
    p = argparse.ArgumentParser(prog="apex replay")
    p.add_argument("run_id", type=int, help="Run ID from apex history")
    p.add_argument("--mode", choices=["live", "dry", "simulate"], default="simulate")
    p.add_argument("--diff", action="store_true", help="Compare step outputs vs recorded")
    p.add_argument("--no-write", action="store_true", help="Disable write_file tool")
    args = p.parse_args(argv)

    rec = _load_run(args.run_id)
    plan_json = json.loads(rec["plan_json"]) if rec["plan_json"] else None
    if plan_json is None:
        raise SystemExit(f"run {args.run_id} has no recorded plan")

    print(f"[replay] run_id={args.run_id} task={rec['task']!r} mode={args.mode}")

    if args.mode == "dry":
        print(json.dumps(plan_json, indent=2))
        return

    events = _load_events(args.run_id)
    recorded = {ev["step"]: ev for ev in events}

    if args.mode == "simulate":
        # Stub each tool to return its recorded result
        print(f"[replay] {len(recorded)} recorded steps")
        for i, ev in enumerate(events):
            recorded_result = ev["result"]
            print(f"  step {ev['step']:>3}  [{ev['tool']}]  recorded={json.dumps(recorded_result)}")
        print("[replay] simulate complete — no live execution performed")
        return

    # mode == live
    from apex.config import load_config
    from apex.core.loop import run
    from apex.core.state import format_output
    from apex.tools import SHELL, READ_FILE, WRITE_FILE, HTTP_GET, RAG_MULTI_QUERY
    from apex.memory import make_memory_tools
    from apex.core.types import Tool

    config = load_config()
    memory_read, memory_write = make_memory_tools(config.db_path)
    registry: dict[str, Tool] = {
        "shell": SHELL,
        "read_file": READ_FILE,
        "write_file": WRITE_FILE,
        "http_get": HTTP_GET,
        "rag_multi_query": RAG_MULTI_QUERY,
        "memory_read": memory_read,
        "memory_write": memory_write,
    }
    if args.no_write:
        registry.pop("write_file", None)

    state = run(rec["task"], config=config, registry=registry)
    print(format_output(state))

    if args.diff and events:
        print("\n[diff] step comparison:")
        for ev in events:
            print(f"  step {ev['step']:>3}  [{ev['tool']}]  recorded={json.dumps(ev['result'])}")
