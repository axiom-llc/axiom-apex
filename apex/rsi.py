"""
apex/rsi.py — Recursive Self-Improvement scaffolding

Each cycle:
  1. Run benchmark → compute apex_score
  2. Read own source files
  3. Generate patch via LLM
  4. Validate patch safety
  5. Apply on git branch rsi/cycle-N
  6. Re-run benchmark → compare score
  7. Report delta; human gate before merge
"""
from __future__ import annotations

import json
import math
import os
import re
import shutil
import statistics
import uuid
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

from apex._rsi_sandbox import IsolationError, ResourceLimitError, run as _run_candidate_process

APEX_CMD = [sys.executable, "-m", "apex"]
BENCH_CMD = [sys.executable, "-m", "apex.rsi_offline_bench"]
REPO_ROOT = Path(__file__).parent.parent

# Source files eligible for RSI patching
RSI_SOURCE_FILES = [
    "apex/core/loop.py",
    "apex/core/planner.py",
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


def _require_clean_tree() -> None:
    if _git(["status", "--porcelain"]).stdout.strip():
        raise RuntimeError("RSI requires a clean Git working tree")


def _branch_exists(name: str) -> bool:
    return _git(["show-ref", "--verify", "--quiet", f"refs/heads/{name}"], check=False).returncode == 0


def _create_branch(name: str) -> None:
    if _branch_exists(name):
        raise RuntimeError(f"branch already exists: {name}")
    _git(["checkout", "-b", name])


def _checkout(branch: str) -> None:
    _git(["checkout", branch])


def _apply_patch(patch_text: str) -> bool:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".patch", delete=False) as f:
        f.write(patch_text)
        patch_path = f.name
    try:
        result = _git(["apply", "--whitespace=fix", patch_path], check=False)
        return result.returncode == 0
    finally:
        os.unlink(patch_path)


def _run_candidate(
    candidate_idx: int, patch_text: str, tasks_path: str, mock_bench: bool,
    k: int = 3, *, dataset: str = "train", evidence: dict | None = None,
) -> float | None:
    """Require passing regressions and valid benchmark runs in a scratch worktree."""
    scratch = tempfile.mkdtemp(prefix=f"apex-rsi-cand{candidate_idx}-")
    try:
        if not _validate_patch(patch_text):
            return None
        _git(["worktree", "add", "--detach", scratch, "HEAD"])
        # Admit only the selected benchmark data, never its containing host path.
        task_data = Path(tasks_path).read_bytes()
        with tempfile.NamedTemporaryFile(dir=scratch, suffix=".json") as task_file:
            task_name = Path(task_file.name).name
        Path(scratch, task_name).write_bytes(task_data)
        with tempfile.NamedTemporaryFile(mode="w", suffix=".patch", delete=False, dir=scratch) as f:
            f.write(patch_text)
            patch_path = f.name
        applied = subprocess.run(
            ["git", "apply", "--whitespace=fix", patch_path],
            cwd=scratch, capture_output=True, text=True,
        )
        os.unlink(patch_path)
        if applied.returncode != 0:
            return None
        validation = _run_candidate_process(
            [sys.executable, "-m", "pytest", "tests", "-m", "not integration and not host_isolation", "-q"],
            scratch,
        )
        if validation.returncode != 0:
            print(f"[rsi] candidate {candidate_idx} failed regression tests\n"
                  f"{validation.stdout[-4000:]}{validation.stderr[-4000:]}", file=sys.stderr)
            return None
        scores = []
        observed = []
        for _ in range(k):
            cmd = BENCH_CMD + ["--tasks", f"/work/{task_name}"]
            if mock_bench:
                cmd.append("--mock")
            if dataset != "train":
                cmd.extend(["--dataset", dataset])
            result = _run_candidate_process(cmd, scratch)
            if result.returncode != 0:
                return None
            try:
                payload = json.loads(result.stdout)
                score = payload["apex_score"]
                if type(score) not in (int, float) or not math.isfinite(score) or not 0 <= score <= 1:
                    return None
                if evidence is not None:
                    if payload.get("benchmark") != "apex-rsi-offline-v1" or payload.get("dataset") != dataset or payload.get("mock") is not False or payload.get("passed") is not True:
                        return None
                    p50, p95 = payload.get("p50_ms"), payload.get("p95_ms")
                    if any(type(x) not in (int, float) or not math.isfinite(x) or x <= 0 for x in (p50, p95)):
                        return None
                    observed.append((float(p50), float(p95)))
                scores.append(float(score))
            except (json.JSONDecodeError, KeyError, TypeError):
                return None
        if scores and evidence is not None:
            evidence.update({
                "apex_score": statistics.median(scores),
                "p50_ms": statistics.median(v[0] for v in observed),
                "p95_ms": statistics.median(v[1] for v in observed),
                "dataset": dataset, "samples": len(observed),
            })
        return statistics.median(scores) if scores else None
    except ResourceLimitError as exc:
        print(f"[rsi] candidate {candidate_idx} rejected: {exc}", file=sys.stderr)
        return None
    except subprocess.TimeoutExpired:
        print(f"[rsi] candidate {candidate_idx} validation timed out", file=sys.stderr)
        return None
    finally:
        _git(["worktree", "remove", "--force", scratch], check=False)
        shutil.rmtree(scratch, ignore_errors=True)


def _commit_cycle(cycle: int, score_before: float, score_after: float) -> None:
    _git(["add", "-A"])
    _git(["commit", "-m",
          f"rsi: cycle-{cycle} score {score_before:.6f} -> {score_after:.6f}"])


# ---------------------------------------------------------------------------
# Bench wrapper
# ---------------------------------------------------------------------------

def _run_bench(tasks_path: str, mock: bool = False, *, dataset: str = "train", k: int = 3) -> dict:
    """Benchmark the current pinned HEAD inside the same offline boundary as candidates.

    No provider calls or host-side scoring. Missing, failed and mock measurements
    cannot be used to authorize RSI.
    """
    if mock:
        raise RuntimeError("mock benchmarks cannot establish an RSI baseline")
    scratch = tempfile.mkdtemp(prefix="apex-rsi-baseline-")
    try:
        _git(["worktree", "add", "--detach", scratch, "HEAD"])
        task_name = "rsi-tasks.json"
        Path(scratch, task_name).write_bytes(Path(tasks_path).read_bytes())
        samples = []
        for _ in range(k):
            cmd = BENCH_CMD + ["--tasks", f"/work/{task_name}", "--dataset", dataset]
            result = _run_candidate_process(cmd, scratch)
            if result.returncode != 0:
                raise RuntimeError("baseline benchmark failed")
            payload = json.loads(result.stdout)
            score = payload.get("apex_score")
            p50, p95 = payload.get("p50_ms"), payload.get("p95_ms")
            if (payload.get("benchmark") != "apex-rsi-offline-v1"
                or payload.get("dataset") != dataset or payload.get("mock") is not False
                or payload.get("passed") is not True
                or any(type(x) not in (int, float) or not math.isfinite(x) or x <= 0 for x in (p50, p95))
                or type(score) not in (int, float) or not math.isfinite(score) or not 0 < score <= 1):
                raise RuntimeError("invalid or incomplete baseline benchmark")
            samples.append(payload)
        return {
            "apex_score": statistics.median(row["apex_score"] for row in samples),
            "p50_ms": statistics.median(row["p50_ms"] for row in samples),
            "p95_ms": statistics.median(row["p95_ms"] for row in samples),
            "dataset": dataset, "samples": len(samples),
        }
    finally:
        _git(["worktree", "remove", "--force", scratch], check=False)
        shutil.rmtree(scratch, ignore_errors=True)


def _material_gain(baseline: dict, candidate: dict, *, min_ms: float = 1.0,
                   min_fraction: float = 0.02, max_p95_regression: float = 0.10) -> bool:
    """A materially faster median with bounded tail, without metric substitution."""
    if baseline.get("dataset") != candidate.get("dataset"):
        return False
    try:
        before, after = float(baseline["p50_ms"]), float(candidate["p50_ms"])
        tail_before, tail_after = float(baseline["p95_ms"]), float(candidate["p95_ms"])
        return (all(math.isfinite(x) and x > 0 for x in (before, after, tail_before, tail_after))
                and before - after >= max(min_ms, min_fraction * before)
                and tail_after <= tail_before * (1 + max_p95_regression)
                and candidate["apex_score"] > baseline["apex_score"])
    except (KeyError, TypeError, ValueError):
        return False


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
# Patch safety validation
# ---------------------------------------------------------------------------

def _validate_patch(patch_text: str) -> bool:
    """Reject unsafe additions and patches outside the explicit RSI allowlist."""
    if any(line == "GIT binary patch" or line.startswith("Binary files ")
           for line in patch_text.splitlines()):
        print("[rsi] binary patches are not permitted", file=sys.stderr)
        return False
    blocked = (
        re.compile(r"rm\s+-[rf]+\s+/"),
        re.compile(r"chmod\s+777\s+/"),
        re.compile(r"curl\s+.*\|\s*sh"),
        re.compile(r"wget\s+.*\|\s*sh"),
        re.compile(r"dd\s+if=/dev/zero"),
        re.compile(r"mkfs\."),
        re.compile(r":\(\)\{:\|:&\};"),
    )
    added = "\n".join(
        line[1:]
        for line in patch_text.splitlines()
        if line.startswith("+") and not line.startswith("+++")
    ).lower()
    for pattern in blocked:
        if pattern.search(added):
            print(f"[rsi] patch contains blocked pattern: {pattern.pattern}", file=sys.stderr)
            return False

    # Ask the same parser used for application: textual header scans miss
    # unprefixed/quoted paths and metadata-only changes in mixed diffs.
    parsed = subprocess.run(
        ["git", "apply", "--numstat", "-z", "-"],
        input=patch_text, cwd=REPO_ROOT, capture_output=True, text=True,
    )
    if parsed.returncode != 0 or not parsed.stdout:
        print("[rsi] patch is malformed or contains no changes", file=sys.stderr)
        return False
    allowed = set(RSI_SOURCE_FILES)
    for record in parsed.stdout.rstrip("\0").split("\0"):
        fields = record.split("\t", 2)
        if len(fields) != 3 or fields[2] not in allowed or "-" in fields[:2]:
            print("[rsi] patch contains a non-RSI target or binary change", file=sys.stderr)
            return False

    # RSI edits existing source text only. Reject creation, deletion, renames,
    # copies and mode changes (including conversion to symbolic links).
    summary = subprocess.run(
        ["git", "apply", "--summary", "-"],
        input=patch_text, cwd=REPO_ROOT, capture_output=True, text=True,
    )
    if summary.returncode != 0 or summary.stdout:
        print("[rsi] patch changes file identity or mode", file=sys.stderr)
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
    """Bounded cumulative candidate optimization; main remains unchanged."""
    if mock_bench:
        raise RuntimeError("mock benchmark cannot authorize an RSI change")
    _require_clean_tree()
    with tempfile.TemporaryDirectory(prefix="apex-rsi-preflight-") as scratch:
        _run_candidate_process([sys.executable, "-c", "pass"], scratch)
    origin_branch = _current_branch()
    if origin_branch == "HEAD":
        raise RuntimeError("RSI requires a named Git branch")
    governor = CycleGovernor(max_cycles=cycles, budget_tokens=budget_tokens,
                             max_wall_seconds=3600.0)
    run_tag = f"{_git(['rev-parse', '--short', 'HEAD']).stdout.strip()}-{uuid.uuid4().hex[:8]}"
    parent_branch = origin_branch
    accepted = []
    results_log: list[dict] = []

    for cycle in range(1, cycles + 1):
        ok, reason = governor.check(cycle)
        if not ok:
            results_log.append({"cycle": cycle, "outcome": "STOP_BUDGET", "reason": reason})
            break
        _checkout(parent_branch)
        branch = f"rsi/{run_tag}/cycle-{cycle}"
        _create_branch(branch)
        keep = False
        try:
            baseline = _run_bench(tasks_path, dataset="train")
            holdout_baseline = _run_bench(tasks_path, dataset="holdout")
            sources = _read_sources()
            candidates = []
            for ci in range(3):
                # Estimated tokens are admission accounting only, never provider-billed usage.
                estimated_prompt_tokens = len(sources.encode("utf-8")) // 4 + 1024
                if governor.tokens_remaining() < estimated_prompt_tokens:
                    break
                patch = _generate_patch(api_key, sources, baseline["apex_score"],
                                        governor.tokens_remaining())
                governor.consume_tokens(estimated_prompt_tokens)
                if not patch or not _validate_patch(patch):
                    continue
                metrics: dict = {}
                candidate_score = _run_candidate(ci, patch, tasks_path, False,
                                                 evidence=metrics)
                if candidate_score is None or not _material_gain(baseline, metrics):
                    continue
                candidates.append((candidate_score, patch, metrics))
            if not candidates:
                results_log.append({"cycle": cycle, "outcome": "NO_MATERIAL_CANDIDATE"})
                break

            # Holdout is separately executed on the patched scratch worktree.
            candidates.sort(key=lambda row: (-row[0], row[2]["p95_ms"]))
            for best_score, best_patch, train_metrics in candidates:
                holdout_metrics: dict = {}
                holdout_score = _run_candidate(99, best_patch, tasks_path, False,
                                               dataset="holdout", evidence=holdout_metrics)
                if holdout_score is None or not _material_gain(holdout_baseline, holdout_metrics):
                    continue
                if not _apply_patch(best_patch):
                    continue
                _commit_cycle(cycle, baseline["apex_score"], best_score)
                keep = True
                parent_branch = branch
                accepted.append(branch)
                results_log.append({
                    "cycle": cycle, "outcome": "ACCEPTED_REVIEW_REQUIRED",
                    "branch": branch, "train_baseline": baseline,
                    "train_candidate": train_metrics, "holdout_baseline": holdout_baseline,
                    "holdout_candidate": holdout_metrics,
                    "token_budget_type": "estimated_only",
                })
                break
            if not keep:
                results_log.append({"cycle": cycle, "outcome": "HOLDOUT_REJECTED"})
                break
        except IsolationError:
            raise
        finally:
            _checkout(origin_branch)
            if not keep:
                _git(["branch", "-D", branch], check=False)

    print(json.dumps({
        "rsi_results": results_log, "accepted_branches": accepted,
        "origin_unchanged": origin_branch,
        "estimated_tokens_used": governor.budget_tokens - governor.tokens_remaining(),
        "provider_tokens_and_cost": None,
        "elapsed_seconds": round(governor.wall_elapsed(), 3),
        "review_required": True,
    }, indent=2))
    if accepted:
        print("[rsi] human review required; no merge or release performed", flush=True)


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
    parser.add_argument("--tasks", default="benchmarks/tasks.json",
                        help="Benchmark tasks.json path")
    parser.add_argument("--mock-bench", action="store_true",
                        help="Use mock benchmark (no real apex calls)")
    args = parser.parse_args(argv)
    if args.cycles <= 0:
        parser.error("--cycles must be greater than 0")
    if args.budget_tokens <= 0:
        parser.error("--budget-tokens must be greater than 0")

    api_key = os.environ.get("GEMINI_API_KEY", "")
    if (
        not api_key
        and os.environ.get("LLM_PROVIDER", "gemini").lower() == "gemini"
    ):
        print("ERROR: GEMINI_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    run_rsi(
        cycles=args.cycles,
        budget_tokens=args.budget_tokens,
        tasks_path=args.tasks,
        mock_bench=args.mock_bench,
        api_key=api_key,
    )
