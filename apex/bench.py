"""
apex/rsi.py — Recursive Self-Improvement scaffolding

Each cycle:
  1. Run benchmark → compute apex_score
  2. Read own source files
  3. Generate patch via LLM
  4. Paranoid-validate patch
  5. Apply on git branch rsi/cycle-N
  6. Re-run benchmark → compare score
  7. Report delta; human gate before merge
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

APEX_CMD = [sys.executable, "-m", "apex"]
BENCH_CMD = [sys.executable, "-m", "apex.bench"]
REPO_ROOT = Path(__file__).parent.parent

# Source files eligible for RSI patching
RSI_SOURCE_FILES = [
    "apex/core/loop.py",
    "apex/core/planner.py",
    "apex/llm.py",
]


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def _git(args: list[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git"] + args,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=check,
    )


def _current_branch() -> str:
    return _git(["rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()


def _create_branch(name: str) -> None:
    _git(["checkout", "-b", name])


def _checkout(branch: str) -> None:
    _git(["checkout", branch])


def _apply_patch(patch_text: str) -> bool:
    """Apply unified diff patch. Returns True on success."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".patch", delete=False) as f:
        f.write(patch_text)
        patch_path = f.name
    result = subprocess.run(
        ["patch", "-p1", "--dry-run", "--fuzz=3", "-i", patch_path],
        cwd=REPO_ROOT, capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"[rsi] patch --dry-run failed: {result.stderr[:300]}", file=sys.stderr)
        return False
    subprocess.run(["patch", "-p1", "--fuzz=3", "-i", patch_path], cwd=REPO_ROOT, check=True)
    Path(patch_path).unlink(missing_ok=True)
    return True


def _run_candidate(
    candidate_idx: int,
    patch_text: str,
    tasks_path: str,
    mock_bench: bool,
    k: int = 3,
) -> float:
    """Apply patch to isolated tmpdir copy, bench k times, return mean score."""
    import shutil
    tmpdir = Path(tempfile.mkdtemp(prefix=f"rsi_cand{candidate_idx}_"))
    try:
        shutil.copytree(REPO_ROOT, tmpdir / "repo", dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns(".git", ".venv", "__pycache__"))
        with tempfile.NamedTemporaryFile(mode="w", suffix=".patch", delete=False) as f:
            f.write(patch_text)
            patch_path = f.name
        dry = subprocess.run(
            ["patch", "-p1", "--dry-run", "--fuzz=3", "-i", patch_path],
            cwd=tmpdir / "repo", capture_output=True, text=True,
        )
        if dry.returncode != 0:
            return 0.0
        subprocess.run(["patch", "-p1", "--fuzz=3", "-i", patch_path],
                       cwd=tmpdir / "repo", check=True, capture_output=True)
        Path(patch_path).unlink(missing_ok=True)
        scores = []
        for _ in range(k):
            cmd = [sys.executable, "-m", "apex.bench", "--tasks", tasks_path]
            if mock_bench:
                cmd.append("--mock")
            r = subprocess.run(cmd, capture_output=True, text=True,
                               cwd=tmpdir / "repo",
                               env={**os.environ, "PYTHONPATH": str(tmpdir / "repo")})
            try:
                scores.append(json.loads(r.stdout).get("apex_score", 0.0))
            except json.JSONDecodeError:
                scores.append(0.0)
        return sum(scores) / len(scores) if scores else 0.0
    except Exception as e:
        print(f"[rsi] candidate {candidate_idx} error: {e}", file=sys.stderr)
        return 0.0
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def _commit_cycle(cycle: int, score_before: float, score_after: float) -> None:
    _git(["add", "-A"])
    _git(["commit", "-m",
          f"rsi: cycle-{cycle} score {score_before:.6f} -> {score_after:.6f}"])


# ---------------------------------------------------------------------------
# Bench wrapper
# ---------------------------------------------------------------------------

def _run_bench(tasks_path: str, mock: bool = False) -> dict[str, Any]:
    cmd = BENCH_CMD + ["--tasks", tasks_path]
    if mock:
        cmd.append("--mock")
    result = subprocess.run(cmd, capture_output=True, text=True)
    try:
        # bench writes JSON to stdout
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"apex_score": 0.0, "error": result.stderr[:512]}


# ---------------------------------------------------------------------------
# Patch generation via LLM
# ---------------------------------------------------------------------------

def _read_sources() -> str:
    parts = []
    for rel in RSI_SOURCE_FILES:
        p = REPO_ROOT / rel
        if p.exists():
            parts.append(f"### {rel}\n```python\n{p.read_text()}\n```")
    return "\n\n".join(parts)


def _generate_patch(api_key: str, sources: str, score: float,
                    budget_tokens: int) -> str | None:
    """Call LLM to produce a unified diff improving apex_score."""
    from apex.llm import gemini_complete

    prompt = (
        f"You are an expert Python engineer improving the APEX agentic runtime.\n"
        f"Current apex_score: {score:.6f} (higher is better).\n"
        f"apex_score = pass_rate * speed_factor * token_efficiency\n\n"
        f"Source files:\n{sources}\n\n"
        f"Produce a minimal unified diff (git diff format) that improves apex_score "
        f"by reducing token usage or wall time without breaking correctness.\n"
        f"Output ONLY the raw unified diff, no explanation, no markdown fences."
    )

    try:
        response = gemini_complete(
            prompt=prompt,
            api_key=api_key,
        )
        text = response.get('text', '') if isinstance(response, dict) else response
        if not text:
            return None
        text = text.replace('```diff', '').replace('```', '')
        lines = text.splitlines(keepends=True)
        start = next((i for i, l in enumerate(lines) if l.startswith('--- ')), None)
        if start is None:
            return None
        out = []
        in_file = False
        for l in lines[start:]:
            if l.startswith('--- '):
                if in_file and out and out[-1].strip() != '':
                    out.append('\n')
                in_file = True
            elif l.startswith('@@ ') and not in_file:
                continue
            if in_file:
                out.append(l)
        text = ''.join(out)
        return text.strip() if text.strip() else None
    except Exception as e:
        print(f"[rsi] LLM patch generation failed: {e}", file=sys.stderr)
        return None


# ---------------------------------------------------------------------------
# Paranoid validation of patch
# ---------------------------------------------------------------------------

def _validate_patch(patch_text: str, api_key: str) -> bool:
    """Structural safety check on unified diff."""
    banned = [":(){:|:&};", "chmod 777 /", "curl.*|.*sh", "wget.*|.*sh"]
    added = "\n".join(l[1:] for l in patch_text.splitlines() if l.startswith("+") and not l.startswith("+++")).lower()
    for pattern in banned:
        if pattern in added:
            print(f"[rsi] patch contains banned pattern: {pattern}", file=sys.stderr)
            return False
    import re
    targets = re.findall(r"^\+\+\+ b/(.+)$", patch_text, re.MULTILINE)
    for t in targets:
        if not any(t.startswith(allowed.lstrip("/")) for allowed in RSI_SOURCE_FILES):
            print(f"[rsi] patch targets non-RSI file: {t}", file=sys.stderr)
            return False
    return True


# ---------------------------------------------------------------------------
# Governor
# ---------------------------------------------------------------------------

class CycleGovernor:
    def __init__(self, max_cycles: int, budget_tokens: int, max_wall_seconds: float):
        self.max_cycles = max_cycles
        self.budget_tokens = budget_tokens
        self.max_wall_seconds = max_wall_seconds
        self._tokens_used = 0
        self._wall_start = time.time()

    def tokens_remaining(self) -> int:
        return max(0, self.budget_tokens - self._tokens_used)

    def consume_tokens(self, n: int) -> None:
        self._tokens_used += n

    def wall_elapsed(self) -> float:
        return time.time() - self._wall_start

    def check(self, cycle: int) -> tuple[bool, str]:
        if cycle > self.max_cycles:
            return False, f"max_cycles={self.max_cycles} reached"
        if self.tokens_remaining() == 0:
            return False, f"budget_tokens={self.budget_tokens} exhausted"
        if self.wall_elapsed() > self.max_wall_seconds:
            return False, f"max_wall_seconds={self.max_wall_seconds} exceeded"
        return True, ""


# ---------------------------------------------------------------------------
# Main RSI loop
# ---------------------------------------------------------------------------

def run_rsi(
    cycles: int,
    budget_tokens: int,
    tasks_path: str,
    mock_bench: bool,
    api_key: str,
) -> None:
    origin_branch = _current_branch()
    governor = CycleGovernor(
        max_cycles=cycles,
        budget_tokens=budget_tokens,
        max_wall_seconds=3600.0,
    )

    print(f"[rsi] starting on branch '{origin_branch}'", flush=True)
    print(f"[rsi] cycles={cycles} budget_tokens={budget_tokens}", flush=True)

    # Baseline score
    baseline = _run_bench(tasks_path, mock=mock_bench)
    score = baseline.get("apex_score", 0.0)
    print(f"[rsi] baseline apex_score={score:.6f}", flush=True)

    results_log: list[dict] = []

    for cycle in range(1, cycles + 1):
        ok, reason = governor.check(cycle)
        if not ok:
            print(f"[rsi] governor halt: {reason}", flush=True)
            break

        branch = f"rsi/cycle-{cycle}"
        print(f"\n[rsi] === cycle {cycle} / {cycles} ===", flush=True)

        # Create branch
        _checkout(origin_branch)
        _create_branch(branch)

        try:
            sources = _read_sources()
            remaining = governor.tokens_remaining()

            # Multi-candidate: generate N=3 patches, score each in isolation
            N_CANDIDATES = 3
            candidates = []
            for ci in range(N_CANDIDATES):
                patch = _generate_patch(api_key, sources, score, remaining)
                if not patch:
                    continue
                if not _validate_patch(patch, api_key):
                    print(f"[rsi] candidate {ci} rejected by paranoid", flush=True)
                    continue
                estimated_tokens = len(patch) // 4 + len(sources) // 4
                governor.consume_tokens(estimated_tokens)
                cand_score = _run_candidate(ci, patch, tasks_path, mock_bench, k=3)
                print(f"[rsi] candidate {ci} score={cand_score:.6f}", flush=True)
                candidates.append((cand_score, patch))

            if not candidates:
                print(f"[rsi] no valid candidates — skipping cycle", flush=True)
                _checkout(origin_branch)
                _git(["branch", "-D", branch])
                continue

            best_score, best_patch = max(candidates, key=lambda x: x[0])
            print(f"[rsi] best candidate score={best_score:.6f} "
                  f"(from {len(candidates)} candidates)", flush=True)

            # Apply best patch to working tree
            if not _apply_patch(best_patch):
                print(f"[rsi] best patch apply failed — skipping cycle", flush=True)
                _checkout(origin_branch)
                _git(["branch", "-D", branch])
                continue

            new_score = best_score
            delta = new_score - score

            print(f"[rsi] score: {score:.6f} -> {new_score:.6f}  delta={delta:+.6f}",
                  flush=True)

            _commit_cycle(cycle, score, new_score)

            results_log.append({
                "cycle": cycle,
                "branch": branch,
                "score_before": score,
                "score_after": new_score,
                "delta": delta,
                "tokens_used": estimated_tokens,
            })

            if new_score > score:
                score = new_score
                print(f"[rsi] improvement on branch '{branch}'", flush=True)
                print(f"[rsi] HUMAN REVIEW REQUIRED before merging '{branch}' -> '{origin_branch}'",
                      flush=True)
            else:
                print(f"[rsi] no improvement — branch '{branch}' retained for inspection",
                      flush=True)

        except Exception as e:
            print(f"[rsi] cycle {cycle} error: {e}", file=sys.stderr)
            _checkout(origin_branch)
            _git(["branch", "-D", branch], check=False)

        finally:
            _checkout(origin_branch)

    print(f"\n[rsi] complete. wall={governor.wall_elapsed():.1f}s "
          f"tokens_used={governor.budget_tokens - governor.tokens_remaining()}",
          flush=True)
    print(json.dumps({"rsi_results": results_log}, indent=2))


# ---------------------------------------------------------------------------
# CLI entry (called from __main__.py dispatch)
# ---------------------------------------------------------------------------

def rsi_main(argv: list[str]) -> None:
    import argparse
    parser = argparse.ArgumentParser(prog="apex rsi")
    parser.add_argument("--cycles", type=int, default=3,
                        help="Number of RSI cycles (default: 3)")
    parser.add_argument("--budget-tokens", type=int, default=50000,
                        help="Max total tokens across all cycles (default: 50000)")
    parser.add_argument("--tasks", default="apex/benchmarks/tasks.json",
                        help="Benchmark tasks.json path")
    parser.add_argument("--mock-bench", action="store_true",
                        help="Use mock benchmark (no real apex calls)")
    args = parser.parse_args(argv)

    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key and not args.mock_bench:
        print("ERROR: GEMINI_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    run_rsi(
        cycles=args.cycles,
        budget_tokens=args.budget_tokens,
        tasks_path=args.tasks,
        mock_bench=args.mock_bench,
        api_key=api_key,
    )
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
    parser.add_argument("--timeout", type=int, default=180,
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

    pass_rate = round(passed / len(results), 4) if results else 0.0
    avg_duration = sum(r["duration_seconds"] for r in results) / len(results) if results else 0.0
    # speed_factor: 1.0 at 10s/task, degrades linearly; floor 0.01
    speed_factor = round(max(0.01, 1.0 - (avg_duration - 10.0) / 200.0), 4)
    # token_efficiency: from history DB if available, else 1.0
    try:
        from apex.history import aggregate_stats as _astats
        _s = _astats()
        _avg_tok = _s["avg_tokens"] or 1.0
        # normalise: 1.0 at 1000 tokens, degrades linearly; floor 0.01
        token_efficiency = round(max(0.01, 1.0 - (_avg_tok - 1000.0) / 50000.0), 4)
    except Exception:
        token_efficiency = 1.0
    apex_score = round(pass_rate * speed_factor * token_efficiency, 6)
    output = {
        "benchmark": "apex_task_harness",
        "mock": args.mock,
        "task_count": len(results),
        "passed": passed,
        "failed": failed,
        "wall_seconds": wall_total,
        "pass_rate": pass_rate,
        "speed_factor": speed_factor,
        "token_efficiency": token_efficiency,
        "apex_score": apex_score,
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
