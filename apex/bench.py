#!/usr/bin/env python3
"""
apex/bench.py — APEX task benchmark harness

Loads tasks.json, runs each task via apex subprocess, records
timing/pass/fail, writes JSON results.

Usage:
    python -m apex.bench --tasks apex/benchmarks/tasks.json
    python -m apex.bench --tasks apex/benchmarks/tasks.json --mock
    python -m apex.bench --tasks apex/benchmarks/tasks.json --trace-path /tmp/bench.jsonl
    python -m apex.bench --tasks apex/benchmarks/tasks.json --out apex/benchmarks/results/run.json

tasks.json schema:
    [
      {
        "id": "write_file",
        "prompt": "write 'hello' to /tmp/apex-bench-out.txt",
        "check": "hello",          # optional: substring expected in output file or stdout
        "check_file": "/tmp/..."   # optional: file whose content is checked
      },
      ...
    ]

Exit codes:
    0 — all tasks passed
    1 — one or more tasks failed
    2 — tasks.json not found or invalid
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

APEX_CMD = [sys.executable, "-m", "apex"]


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def run_task(
    task: dict[str, Any],
    *,
    mock: bool,
    trace_path: str | None,
    timeout: int,
    work_dir: str,
) -> dict[str, Any]:
    task_id = task["id"]
    prompt = task["prompt"]
    check = task.get("check")
    check_file = task.get("check_file")

    # Resolve check_file relative to work_dir if it's a bare filename
    if check_file and not os.path.isabs(check_file):
        check_file = str(Path(work_dir) / check_file)
        prompt = prompt.replace(task.get("check_file", ""), check_file)

    if mock:
        time.sleep(0.05)
        return {
            "id": task_id,
            "duration_seconds": 0.05,
            "exit_code": 0,
            "passed": True,
            "mock": True,
        }

    cmd = list(APEX_CMD)
    if trace_path:
        cmd += ["--full-trace", "--trace-path", trace_path]
    cmd.append(prompt)

    start = time.perf_counter()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {
            "id": task_id,
            "duration_seconds": timeout,
            "exit_code": -1,
            "passed": False,
            "error": "timeout",
        }
    elapsed = time.perf_counter() - start

    passed = result.returncode == 0

    # Optional content check
    if passed and check:
        if check_file:
            p = Path(check_file)
            if p.exists():
                passed = check.lower() in p.read_text().lower()
            else:
                passed = False
        else:
            combined = result.stdout + result.stderr
            passed = check.lower() in combined.lower()

    return {
        "id": task_id,
        "duration_seconds": round(elapsed, 3),
        "exit_code": result.returncode,
        "passed": passed,
        "stdout": result.stdout[:512] if not passed else "",
        "stderr": result.stderr[:512] if not passed else "",
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="APEX benchmark harness")
    parser.add_argument("--tasks", default="apex/benchmarks/tasks.json",
                        help="Path to tasks.json (default: apex/benchmarks/tasks.json)")
    parser.add_argument("--mock", action="store_true",
                        help="Skip real apex calls (for CI without API key)")
    parser.add_argument("--trace-path", default=None,
                        help="Pass --full-trace --trace-path to each apex call")
    parser.add_argument("--out", default=None,
                        help="Write JSON results to this path (default: stdout only)")
    parser.add_argument("--timeout", type=int, default=120,
                        help="Per-task timeout in seconds (default: 120)")
    args = parser.parse_args()

    tasks_path = Path(args.tasks)
    if not tasks_path.exists():
        print(f"ERROR: tasks file not found: {tasks_path}", file=sys.stderr)
        sys.exit(2)

    try:
        tasks = json.loads(tasks_path.read_text())
    except json.JSONDecodeError as e:
        print(f"ERROR: invalid JSON in {tasks_path}: {e}", file=sys.stderr)
        sys.exit(2)

    if not isinstance(tasks, list) or not tasks:
        print(f"ERROR: tasks.json must be a non-empty list", file=sys.stderr)
        sys.exit(2)

    if not args.mock:
        if not os.environ.get("GEMINI_API_KEY"):
            print("ERROR: GEMINI_API_KEY not set. Use --mock for CI.", file=sys.stderr)
            sys.exit(1)

    print(f"[bench] tasks={len(tasks)} mock={args.mock} timeout={args.timeout}s",
          file=sys.stderr)

    results = []
    wall_start = time.perf_counter()

    with tempfile.TemporaryDirectory(prefix="apex-bench-") as work_dir:
        for i, task in enumerate(tasks):
            print(f"[bench] [{i+1}/{len(tasks)}] {task['id']} ...", file=sys.stderr)
            r = run_task(
                task,
                mock=args.mock,
                trace_path=args.trace_path,
                timeout=args.timeout,
                work_dir=work_dir,
            )
            results.append(r)
            status = "PASS" if r["passed"] else "FAIL"
            print(f"[bench]   {status} {r['duration_seconds']:.2f}s", file=sys.stderr)

    wall_total = round(time.perf_counter() - wall_start, 3)
    passed = sum(1 for r in results if r["passed"])
    failed = len(results) - passed

    output = {
        "benchmark": "apex_task_harness",
        "mock": args.mock,
        "task_count": len(results),
        "passed": passed,
        "failed": failed,
        "wall_seconds": wall_total,
        "results": results,
    }

    json_out = json.dumps(output, indent=2)
    print(json_out)

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json_out)
        print(f"[bench] results written to {args.out}", file=sys.stderr)

    print(f"\n[bench] {passed}/{len(results)} passed  wall={wall_total:.2f}s",
          file=sys.stderr)

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
