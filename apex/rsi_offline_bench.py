"""Deterministic, provider-free candidate/holdout benchmark for APEX RSI.

This is an interpreter-level microbenchmark of actual parsing/normalization code,
not a substitute for full agent, model, tool, or production workload evaluation.
No network, credentials, provider usage or paid calls are involved.
"""
import argparse
import json
import math
import resource
import statistics
import time

from apex.core.planner import _extract_json, _type_name
from apex.core.loop import _normalize_output
from apex.core.types import Ok

_TYPES = (str, int, float, bool, dict, list, object)
_EXPECTED_TYPES = ('string', 'integer', 'number', 'boolean', 'object', 'array', 'any JSON value')


def _sample(seed: int) -> None:
    payload = {"goal": f"case-{seed % 97}", "steps": [{"type": "halt", "reason": "complete"}],
               "nested": {"v": seed % 401, "bool": bool(seed % 2)}}
    response = "```json\n" + json.dumps(payload, separators=(",", ":")) + "\n```"
    parsed = _extract_json(response)
    if parsed != payload:
        raise AssertionError("JSON extraction changed its outcome")
    output = _normalize_output("rsi-probe", {"goal": parsed["goal"], "v": parsed["nested"]["v"]})
    if not isinstance(output, Ok) or output.value["goal"] != payload["goal"]:
        raise AssertionError("output normalization changed its outcome")


def measure(dataset: str, *, rounds: int = 9, cases: int = 4000, type_cases: int = 15000) -> dict:
    if dataset not in {"train", "holdout"} or rounds < 3 or cases <= 0 or type_cases <= 0:
        raise ValueError("invalid fixed benchmark dimensions")
    samples, cpu_samples = [], []
    offset = 100_000 if dataset == "holdout" else 0
    for rep in range(rounds):
        start = time.perf_counter_ns()
        cpu_start = time.process_time_ns()
        for idx in range(cases):
            _sample(offset + idx * 29 + rep * 43)
        for idx in range(type_cases):
            key = (offset + idx * 11 + rep * 3) % len(_TYPES)
            if _type_name(_TYPES[key]) != _EXPECTED_TYPES[key]:
                raise AssertionError("type name changed its outcome")
        samples.append((time.perf_counter_ns() - start) / 1_000_000)
        cpu_samples.append((time.process_time_ns() - cpu_start) / 1_000_000)
    p50 = statistics.median(samples)
    p95 = sorted(samples)[math.ceil(.95 * len(samples)) - 1]
    return {
        "benchmark": "apex-rsi-offline-v1", "dataset": dataset, "mock": False,
        "passed": True, "cases_per_round": cases, "rounds": rounds,
        "type_cases_per_round": type_cases, "work_units_per_round": cases + type_cases,
        "cpu_ms": statistics.median(cpu_samples),
        "peak_rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        "provider_calls": 0, "provider_tokens": 0, "provider_cost_usd": 0,
        "p50_ms": p50, "p95_ms": p95,
        "apex_score": 100 / (100 + p50),
        "provider_tokens": None, "provider_cost": None,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tasks", default=None, help="legacy argument; not used for offline microbenchmark")
    parser.add_argument("--dataset", choices=("train", "holdout"), default="train")
    parser.add_argument("--mock", action="store_true")
    args = parser.parse_args()
    if args.mock:
        print(json.dumps({"benchmark": "mock", "mock": True, "apex_score": 1.0}))
        return
    print(json.dumps(measure(args.dataset), sort_keys=True))


if __name__ == "__main__":
    main()
