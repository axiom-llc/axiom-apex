#!/usr/bin/env python3
"""
benchmarks/parallel_codegen.py — APEX parallelism benchmark

Measures wall-clock time for sequential vs parallel task execution using
bash process isolation (apex's native concurrency model).

Each task is a self-contained codegen prompt: generate a Python function
for a distinct specification and write it to a file.

Usage:
    # Real mode (requires GEMINI_API_KEY, invokes apex):
    python benchmarks/parallel_codegen.py

    # Dry-run mode (no API calls, simulates with sleep):
    python benchmarks/parallel_codegen.py --mock

    # Custom task count:
    python benchmarks/parallel_codegen.py --tasks 6

    # Cap concurrent processes (default: 4):
    python benchmarks/parallel_codegen.py --tasks 8 --concurrency 4

Output:
    JSON to stdout  — machine-readable result
    Summary to stderr — human-readable

Exit codes:
    0 — benchmark completed
    1 — apex not found or API key missing (non-mock mode)
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import NamedTuple

# ---------------------------------------------------------------------------
# Task definitions
# ---------------------------------------------------------------------------

TASKS = [
    "write a Python function called 'binary_search' that searches a sorted list",
    "write a Python function called 'flatten_dict' that flattens a nested dictionary",
    "write a Python function called 'retry' that retries a callable N times on exception",
    "write a Python function called 'chunk' that splits a list into chunks of size N",
    "write a Python function called 'memoize' that caches function results by arguments",
    "write a Python function called 'parse_csv_row' that handles quoted fields correctly",
    "write a Python function called 'rate_limit' that enforces calls per second",
    "write a Python function called 'deep_merge' that merges two dicts recursively",
]


class TaskResult(NamedTuple):
    label: str
    duration_seconds: float
    exit_code: int
    output_path: str


# ---------------------------------------------------------------------------
# Runners
# ---------------------------------------------------------------------------


def run_real_task(task: str, output_path: str, timeout: int = 120) -> TaskResult:
    """Invoke apex for a single task. Blocking."""
    label = output_path.split("/")[-1]
    prompt = f"{task}. Write only the function (no tests, no explanation) to {output_path}"
    start = time.perf_counter()
    result = subprocess.run(
        ["apex", prompt],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    elapsed = time.perf_counter() - start
    return TaskResult(label, elapsed, result.returncode, output_path)


def run_mock_task(task: str, output_path: str, latency: float = 2.5) -> TaskResult:
    """Simulate an apex call with a sleep. Writes a stub file."""
    label = output_path.split("/")[-1]
    start = time.perf_counter()
    time.sleep(latency + (hash(task) % 100) / 100)  # slight variance per task
    Path(output_path).write_text(f"# mock output for: {task}\ndef stub(): pass\n")
    elapsed = time.perf_counter() - start
    return TaskResult(label, elapsed, 0, output_path)


# ---------------------------------------------------------------------------
# Sequential execution
# ---------------------------------------------------------------------------


def run_sequential(tasks, work_dir, run_fn) -> tuple[list[TaskResult], float]:
    results = []
    start = time.perf_counter()
    for i, task in enumerate(tasks):
        out = str(Path(work_dir) / f"task_{i:02d}.py")
        results.append(run_fn(task, out))
    total = time.perf_counter() - start
    return results, total


# ---------------------------------------------------------------------------
# Parallel execution (bash & / wait pattern)
# ---------------------------------------------------------------------------


def run_parallel_bash(
    tasks, work_dir, mock: bool, latency: float, concurrency: int
) -> tuple[list[TaskResult], float]:
    """
    Spawns apex processes concurrently in batches of `concurrency`,
    mirroring the bash `cmd & wait` pattern documented in APEX.
    Batching avoids API rate-limit contention beyond the effective
    concurrency ceiling (~4 for Gemini 2.5 Flash).
    """
    output_paths = [str(Path(work_dir) / f"task_parallel_{i:02d}.py") for i in range(len(tasks))]
    all_results = []
    start_wall = time.perf_counter()

    for batch_start in range(0, len(tasks), concurrency):
        batch_tasks = tasks[batch_start:batch_start + concurrency]
        batch_paths = output_paths[batch_start:batch_start + concurrency]
        procs = []
        start_times = []

        for task, out in zip(batch_tasks, batch_paths):
            if mock:
                variance = (hash(task) % 100) / 100
                sleep_time = latency + variance
                cmd = [
                    "python3", "-c",
                    f"import time, pathlib; time.sleep({sleep_time}); "
                    f"pathlib.Path('{out}').write_text('# mock\\ndef stub(): pass\\n')"
                ]
            else:
                prompt = f"{task}. Write only the function to {out}"
                cmd = ["apex", prompt]

            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            procs.append((proc, out, task))
            start_times.append(time.perf_counter())

        for (proc, out, task), t_start in zip(procs, start_times):
            proc.wait()
            elapsed = time.perf_counter() - t_start
            label = Path(out).name
            all_results.append(TaskResult(label, elapsed, proc.returncode, out))

    total_wall = time.perf_counter() - start_wall
    return all_results, total_wall


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------


def validate_outputs(results: list[TaskResult]) -> dict:
    """Check that each task produced a non-empty output file."""
    report = {"total": len(results), "success": 0, "missing": [], "empty": []}
    for r in results:
        p = Path(r.output_path)
        if not p.exists():
            report["missing"].append(r.label)
        elif p.stat().st_size == 0:
            report["empty"].append(r.label)
        else:
            report["success"] += 1
    return report


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="APEX parallelism benchmark")
    parser.add_argument("--mock", action="store_true", help="Simulate tasks with sleep (no API)")
    parser.add_argument("--tasks", type=int, default=4, help="Number of tasks (1–8, default 4)")
    parser.add_argument("--mock-latency", type=float, default=2.5, help="Simulated task latency in seconds")
    parser.add_argument("--concurrency", type=int, default=4, help="Max parallel processes per batch (default 4)")
    args = parser.parse_args()

    n = max(1, min(args.tasks, len(TASKS)))
    tasks = TASKS[:n]
    mock = args.mock
    concurrency = max(1, args.concurrency)

    if not mock:
        if not os.environ.get("GEMINI_API_KEY"):
            print("ERROR: GEMINI_API_KEY not set. Use --mock for simulation.", file=sys.stderr)
            sys.exit(1)
        if not shutil.which("apex"):
            print("ERROR: apex not found in PATH. Run: pip install -e .", file=sys.stderr)
            sys.exit(1)

    run_fn = (lambda task, out: run_mock_task(task, out, args.mock_latency)) if mock else run_real_task

    print(f"[benchmark] mode={'mock' if mock else 'real'} tasks={n} concurrency={concurrency}", file=sys.stderr)

    with tempfile.TemporaryDirectory(prefix="apex-bench-") as work_dir:
        # Sequential
        print(f"[benchmark] running {n} tasks sequentially...", file=sys.stderr)
        seq_results, seq_total = run_sequential(tasks, work_dir, run_fn)
        seq_validation = validate_outputs(seq_results)

        # Parallel
        print(f"[benchmark] running {n} tasks in parallel (batch_size={concurrency})...", file=sys.stderr)
        par_results, par_total = run_parallel_bash(tasks, work_dir, mock, args.mock_latency, concurrency)
        par_validation = validate_outputs(par_results)

    # Compute speedup
    speedup = seq_total / par_total if par_total > 0 else float("inf")
    efficiency = speedup / n  # ideal = 1.0

    output = {
        "benchmark": "apex_parallel_codegen",
        "mode": "mock" if mock else "real",
        "task_count": n,
        "concurrency": concurrency,
        "sequential": {
            "wall_seconds": round(seq_total, 3),
            "per_task_seconds": [round(r.duration_seconds, 3) for r in seq_results],
            "validation": seq_validation,
        },
        "parallel": {
            "wall_seconds": round(par_total, 3),
            "per_task_seconds": [round(r.duration_seconds, 3) for r in par_results],
            "validation": par_validation,
        },
        "speedup_factor": round(speedup, 2),
        "parallel_efficiency": round(efficiency, 2),
        "notes": (
            "Mock mode: speedup reflects process spawn overhead only. "
            "Real mode: speedup reflects LLM API latency amortization via bash concurrency."
            if mock else
            "Real mode: each apex invocation is an isolated process. "
            "Speedup varies with Gemini API latency and task complexity."
        ),
    }

    print(json.dumps(output, indent=2))

    # Human summary to stderr
    print(f"\n[result] sequential={seq_total:.2f}s  parallel={par_total:.2f}s  speedup={speedup:.2f}×", file=sys.stderr)
    if seq_validation["success"] < n or par_validation["success"] < n:
        print(f"[warning] validation failures detected — check 'missing' and 'empty' fields", file=sys.stderr)


if __name__ == "__main__":
    main()
