"""Independent source-bound APEX planner ablation and acceptance benchmark.

Compares the unmodified pinned production planner, decoder-only, type-map-only,
and cumulative candidates in the *same* runner. Reports raw alternating
measurements, CPU, p95, correctness, memory and amortization; never invents
operator labor savings or LLM provider usage.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
from pathlib import Path
import resource
import statistics
import subprocess
import time
import tracemalloc

from apex.core.types import Err, Plan, Tool
from apex.rsi_candidate_rules import _decoder_rule, _mapping_rule

MODES = ("baseline", "decoder", "types", "cumulative")
TYPES = (str, int, bool, dict, list, float, object)


def _source(ref: str) -> str:
    if len(ref) != 40 or any(x not in "0123456789abcdef" for x in ref):
        raise ValueError("baseline must be a pinned 40-character commit")
    return subprocess.check_output(
        ["git", "show", ref + ":apex/core/planner.py"], text=True
    )


def _compile_variants(base: str, current: str) -> tuple[dict, dict]:
    decoder = _decoder_rule(base)
    type_map = _mapping_rule(base)
    cumulative = _mapping_rule(decoder) if decoder is not None else None
    if not decoder or not type_map or not cumulative or cumulative != current:
        raise AssertionError("candidate no longer matches the two source-generated rules")
    source_map = {
        "baseline": base,
        "decoder": decoder,
        "types": type_map,
        "cumulative": cumulative,
    }
    modules = {}
    for mode, source in source_map.items():
        namespace = {"__name__": "apex.core.planner_ablation_" + mode}
        exec(compile(source, "apex/core/planner.py::" + mode, "exec"), namespace)
        modules[mode] = namespace
    return modules, {k: hashlib.sha256(v.encode()).hexdigest()
                     for k, v in source_map.items()}


def _fixtures() -> tuple[dict[str, Tool], list[str]]:
    noop = lambda args: args
    registry = {
        "fetch": Tool(
            "fetch", {"url": str, "count": int, "fresh": bool},
            {"text": str, "cost": float}, noop, required=frozenset({"url"}),
        ),
        "echo": Tool(
            "echo", {"payload": dict, "tags": list}, {"payload": dict}, noop
        ),
        "value": Tool("value", {"data": object}, {"data": object}, noop),
        "calc": Tool("calc", {"n": int, "v": float}, {"n": float}, noop),
    }
    cases = []
    for idx in range(128):
        steps = [{
            "type": "tool", "name": "fetch",
            "args": {"url": "https://example.invalid/r/" + str(idx),
                     "count": idx % 7, "fresh": idx % 2 == 0},
        }, {"type": "halt", "reason": "done"}]
        if idx % 11 == 0:
            steps[0]["args"]["count"] = "not-an-int"
        if idx % 13 == 0:
            steps[0]["name"] = "unknown"
        if idx % 17 == 0:
            steps[1]["type"] = "tool"
        if idx % 19 == 0:
            steps[0]["args"]["rogue"] = 1
        value = json.dumps({"goal": "review-" + str(idx), "steps": steps},
                           separators=(",", ":"))
        if idx % 5 == 0:
            value = "```json\n" + value + "\n```"
        cases.append(value)
    cases += [
        "not json", "{\"goal\":", "[]", "{\"goal\": 3, \"steps\": []}",
        "{\"goal\": \"a\", \"steps\": []}",
    ]
    return registry, cases


def _quality(modules: dict, registry: dict, cases: list[str]) -> dict:
    baseline = modules["baseline"]
    expected = [baseline["parse_plan"](case, registry) for case in cases]
    descriptions = [baseline["_describe_tool"](registry[k]) for k in sorted(registry)]
    prompts = [baseline["render_prompt"]("audit repo ~", registry)]
    errors = sum(isinstance(x, Err) for x in expected)
    accepted = sum(isinstance(x, Plan) for x in expected)
    if not errors or not accepted:
        raise AssertionError("test corpus lacks both accepted and rejected plans")
    fenced = [case for case in cases if case.startswith("```")]
    if len(fenced) < 10 or not isinstance(baseline["_extract_json"](fenced[0]), dict):
        raise AssertionError("fenced JSON fixture parsing is not exercised")
    for name in MODES[1:]:
        variant = modules[name]
        if ([variant["parse_plan"](case, registry) for case in cases] != expected
            or [variant["_describe_tool"](registry[k]) for k in sorted(registry)] != descriptions
            or [variant["render_prompt"]("audit repo ~", registry)] != prompts):
            raise AssertionError("candidate behavior differs from pinned baseline: " + name)
        # Shared JSONDecoder is exercised concurrently, with exact-result matching.
        with ThreadPoolExecutor(max_workers=8) as executor:
            observed = list(executor.map(
                lambda case: variant["parse_plan"](case, registry), cases * 3
            ))
        if observed != expected * 3:
            raise AssertionError("concurrent parsing diverges: " + name)
    return {"cases": len(cases), "accepted": accepted, "errors": errors,
            "concurrent_calls_per_variant": len(cases) * 3,
            "all_modes_equivalent": True}


def _work(namespace: dict, registry: dict, cases: list[str], operations: int,
          *, prompt: bool) -> int:
    parse = namespace["parse_plan"]
    describe = namespace["_describe_tool"]
    render = namespace["render_prompt"]
    keys = tuple(sorted(registry))
    checksum = 0
    for idx in range(operations):
        result = parse(cases[idx % len(cases)], registry)
        checksum += len(result.steps) if isinstance(result, Plan) else len(result.message)
        if idx % 3 == 0:
            checksum += len(describe(registry[keys[idx % len(keys)]]))
        if prompt and idx % 4 == 0:
            checksum += len(render("review repo", registry))
    return checksum


def _measure(namespace: dict, registry: dict, cases: list[str],
             operations: int, *, prompt: bool) -> dict:
    wall_start = time.perf_counter_ns()
    cpu_start = time.process_time_ns()
    checksum = _work(namespace, registry, cases, operations, prompt=prompt)
    return {"wall_ms": (time.perf_counter_ns() - wall_start) / 1e6,
            "cpu_ms": (time.process_time_ns() - cpu_start) / 1e6,
            "checksum": checksum}


def _percentile(values: list[float], proportion: float) -> float:
    ordered = sorted(values)
    return ordered[math.ceil(proportion * len(values)) - 1]


def _stats(rows: list[dict]) -> dict:
    return {
        "wall_p50_ms": statistics.median(x["wall_ms"] for x in rows),
        "wall_p95_ms": _percentile([x["wall_ms"] for x in rows], .95),
        "cpu_p50_ms": statistics.median(x["cpu_ms"] for x in rows),
        "samples": len(rows),
    }


def measure(base: str, current: str, *, trials: int = 20,
            operations: int = 450) -> dict:
    if not 12 <= trials <= 40 or not 100 <= operations <= 2000:
        raise ValueError("bounded benchmark dimensions only")
    started = time.perf_counter_ns()
    modules, digests = _compile_variants(base, current)
    registry, cases = _fixtures()
    quality = _quality(modules, registry, cases)
    cohorts = {}
    for cohort, prompt in (("planner_cpu", False), ("plan_render_and_parse", True)):
        for mode in MODES:
            for _ in range(3):
                _work(modules[mode], registry, cases, operations, prompt=prompt)
        observations = {mode: [] for mode in MODES}
        for turn in range(trials):
            order = MODES[turn % len(MODES):] + MODES[:turn % len(MODES)]
            if (turn // len(MODES)) % 2:
                order = tuple(reversed(order))
            expected = None
            for mode in order:
                sample = _measure(modules[mode], registry, cases,
                                  operations, prompt=prompt)
                if expected is None:
                    expected = sample["checksum"]
                elif sample["checksum"] != expected:
                    raise AssertionError("timed output fingerprint changed")
                observations[mode].append(sample)
        cohorts[cohort] = {
            "observations": observations,
            "summary": {mode: _stats(observations[mode]) for mode in MODES},
        }
    memory = {}
    for mode in MODES:
        tracemalloc.start()
        _work(modules[mode], registry, cases, operations, prompt=False)
        _, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()
        memory[mode] = peak
    primary = cohorts["planner_cpu"]["summary"]
    secondary = cohorts["plan_render_and_parse"]["summary"]
    base_measure = primary["baseline"]
    admission = {}
    for mode in MODES[1:]:
        row = primary[mode]
        delta = base_measure["wall_p50_ms"] - row["wall_p50_ms"]
        # The older RSI 1 ms gate was calibrated to 19,000 operations.
        # Retain that per-operation floor when using 450-operation batches.
        min_gain = max(operations / 19000, .05 * base_measure["wall_p50_ms"])
        passes = (delta >= min_gain
                  and row["wall_p95_ms"] <= 1.10 * base_measure["wall_p95_ms"]
                  and row["cpu_p50_ms"] <= 1.05 * base_measure["cpu_p50_ms"]
                  and memory[mode] <= 1.10 * memory["baseline"]
                  and secondary[mode]["wall_p95_ms"] <= 1.10 * secondary["baseline"]["wall_p95_ms"])
        admission[mode] = {
            "accepted": bool(passes),
            "p50_saved_ms_per_fixed_round": delta,
            "p50_reduction_pct": 100 * delta / base_measure["wall_p50_ms"],
            "independent_cohort_p95_ok": (
                secondary[mode]["wall_p95_ms"] <= 1.10 * secondary["baseline"]["wall_p95_ms"]
            ),
        }
    elapsed_ms = (time.perf_counter_ns() - started) / 1e6
    combined_gain = admission["cumulative"]["p50_saved_ms_per_fixed_round"]
    marginal_decoder = primary["baseline"]["wall_p50_ms"] - primary["decoder"]["wall_p50_ms"]
    marginal_type_on_decoder = primary["decoder"]["wall_p50_ms"] - primary["cumulative"]["wall_p50_ms"]
    marginal_floor = max(operations / 19000,
                         .02 * primary["decoder"]["wall_p50_ms"])
    sequential_type_accepted = (
        marginal_type_on_decoder >= marginal_floor
        and primary["cumulative"]["wall_p95_ms"] <= 1.10 * primary["decoder"]["wall_p95_ms"]
        and primary["cumulative"]["cpu_p50_ms"] <= 1.05 * primary["decoder"]["cpu_p50_ms"]
        and memory["cumulative"] <= 1.10 * memory["decoder"]
    )
    admission["cumulative"]["accepted"] &= sequential_type_accepted
    admission["cumulative"]["sequential_type_map_accepted"] = sequential_type_accepted
    admission["cumulative"]["sequential_type_map_gain_ms"] = marginal_type_on_decoder
    return {
        "schema": "axiom-apex/planner-ablation-v1",
        "baseline_sha": hashlib.sha256(base.encode()).hexdigest(),
        "source_sha256": digests,
        "python_workload": "real parse_plan, _describe_tool, render_prompt (no external model calls)",
        "cases": quality,
        "fixed_operations_per_round": operations,
        "trials_per_mode_per_cohort": trials,
        "cohorts": cohorts,
        "memory_peak_bytes_tracemalloc": memory,
        "admission": admission,
        "sequential_decoder_gain_ms": marginal_decoder,
        "sequential_type_map_gain_ms": marginal_type_on_decoder,
        "total_evaluation_ms": elapsed_ms,
        "amortization_rounds": (
            math.ceil(elapsed_ms / combined_gain) if combined_gain > 0 else None
        ),
        "model_calls": 0,
        "provider_cost_usd": 0,
        "github_ci_cost_usd": None,
        "operator_minutes_saved": None,
        "realized_operator_roi": "UNVERIFIED",
        "process_rss_kib_high_water": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-ref", required=True)
    parser.add_argument("--trials", type=int, default=20)
    parser.add_argument("--operations", type=int, default=450)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    base = _source(args.baseline_ref)
    current = Path("apex/core/planner.py").read_text(encoding="utf-8")
    result = measure(base, current, trials=args.trials, operations=args.operations)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print("PLANNER_ABLATION " + json.dumps({
        "source": result["source_sha256"],
        "acceptance": result["admission"],
        "planner_cpu": result["cohorts"]["planner_cpu"]["summary"],
        "end_to_end": result["cohorts"]["plan_render_and_parse"]["summary"],
        "memory": result["memory_peak_bytes_tracemalloc"],
        "evaluation_ms": result["total_evaluation_ms"],
        "amortization_rounds": result["amortization_rounds"],
        "quality": result["cases"],
    }, sort_keys=True))
    if not result["admission"]["cumulative"]["accepted"]:
        raise SystemExit("cumulative planner improvement did not meet independent gate")


if __name__ == "__main__":
    main()
