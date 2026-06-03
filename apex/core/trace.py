"""apex export — dump runs.db to CSV or JSONL"""
import csv
import json
import sqlite3
import sys
from apex.history import DB_PATH

_DEFAULT_FIELDS = ["id", "task", "exit_code", "token_count", "wall_seconds", "timestamp"]


def _load_runs(since: str | None) -> list[dict]:
    con = sqlite3.connect(DB_PATH)
    q = "SELECT id, task, exit_code, token_count, wall_seconds, timestamp FROM runs"
    params = []
    if since:
        q += " WHERE timestamp >= ?"
        params.append(since)
    q += " ORDER BY id ASC"
    rows = con.execute(q, params).fetchall()
    con.close()
    return [dict(zip(_DEFAULT_FIELDS, r)) for r in rows]


def _load_events(run_id: int) -> list[dict]:
    con = sqlite3.connect(DB_PATH)
    rows = con.execute(
        "SELECT step, tool, args_json, result_json FROM events WHERE run_id = ? ORDER BY step",
        (run_id,)
    ).fetchall()
    con.close()
    return [{"step": r[0], "tool": r[1],
             "args": json.loads(r[2]) if r[2] else {},
             "result": json.loads(r[3]) if r[3] else {}} for r in rows]


def export_main(argv: list[str]) -> None:
    import argparse
    p = argparse.ArgumentParser(prog="apex export")
    p.add_argument("--format", choices=["csv", "jsonl"], default="jsonl")
    p.add_argument("--since", default=None, help="ISO timestamp filter e.g. 2026-01-01")
    p.add_argument("--fields", default=None, help="Comma-separated field list")
    p.add_argument("--events", action="store_true", help="Include step-level events")
    p.add_argument("--output", "-o", default=None, help="Output file (default: stdout)")
    args = p.parse_args(argv)

    fields = args.fields.split(",") if args.fields else _DEFAULT_FIELDS
    runs = _load_runs(args.since)

    out = open(args.output, "w", newline="" if args.format == "csv" else "") if args.output else sys.stdout

    try:
        if args.format == "csv":
            writer = csv.DictWriter(out, fieldnames=fields, extrasaction="ignore")
            writer.writeheader()
            for run in runs:
                writer.writerow(run)
        else:  # jsonl
            for run in runs:
                row = {k: run[k] for k in fields if k in run}
                if args.events:
                    row["events"] = _load_events(run["id"])
                out.write(json.dumps(row) + "\n")
    finally:
        if args.output:
            out.close()
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
"""JSONL structured trace writer."""
import json
import sys
from pathlib import Path
from time import time
from typing import Any


def write_event(event: dict[str, Any], *, dest: Path | None = None) -> None:
    """Write a single JSONL trace event to file or stderr."""
    record = {"ts": time(), **event}
    line = json.dumps(record, default=str)
    if dest:
        dest.parent.mkdir(parents=True, exist_ok=True)
        with dest.open("a", encoding="utf-8") as f:
            f.write(line + "\n")
    else:
        print(line, file=sys.stderr)
