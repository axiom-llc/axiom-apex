"""Explicit evaluation-overhead accounting; never invent production volume."""
import argparse
import json
import math
from pathlib import Path


def evaluate(data: dict, *, scenario_rounds: int | None = None) -> dict:
    passes = [r for r in data.get("rsi_results", [])
              if r.get("outcome") == "ACCEPTED_REVIEW_REQUIRED"]
    if not passes:
        return {"status": "NO_ACCEPTED_IMPROVEMENT", "accepted_generations": 0,
                "evaluation_overhead_seconds": data.get("elapsed_seconds"),
                "realized_operational_roi": "UNVERIFIED"}
    initial = passes[0]["holdout_baseline"]
    final = passes[-1]["holdout_candidate"]
    work_units = initial.get("work_units_per_round")
    if type(work_units) is not int or work_units <= 0 or work_units != final.get("work_units_per_round"):
        raise ValueError("independent workload identity invalid")
    saved_ms = initial["p50_ms"] - final["p50_ms"]
    elapsed = data["elapsed_seconds"]
    if (not all(math.isfinite(x) for x in (saved_ms, elapsed))
        or saved_ms <= 0 or elapsed <= 0):
        raise ValueError("no valid aggregate independent positive improvement")
    break_even_rounds = math.ceil(1000 * elapsed / saved_ms)
    if scenario_rounds is not None and (type(scenario_rounds) is not int or scenario_rounds <= 0):
        raise ValueError("scenario rounds must be a positive integer")
    net_s = (scenario_rounds * saved_ms / 1000 - elapsed
             if scenario_rounds is not None else None)
    return {
        "status": "LAB_IMPROVEMENT_ROI_UNVERIFIED",
        "generator": data["generator"],
        "accepted_generations": len(passes),
        "initial_holdout_p50_ms": initial["p50_ms"],
        "final_holdout_p50_ms": final["p50_ms"],
        "initial_holdout_p95_ms": initial["p95_ms"],
        "final_holdout_p95_ms": final["p95_ms"],
        "initial_holdout_cpu_ms": initial.get("cpu_ms"),
        "final_holdout_cpu_ms": final.get("cpu_ms"),
        "initial_holdout_rss_kib": initial.get("peak_rss_kib"),
        "final_holdout_rss_kib": final.get("peak_rss_kib"),
        "machine_ms_saved_per_workload_round": saved_ms,
        "work_units_per_round": work_units,
        "full_evaluation_overhead_seconds": elapsed,
        "amortization_break_even_rounds": break_even_rounds,
        "amortization_break_even_operations": work_units * break_even_rounds,
        "observed_real_workload_rounds": None,
        "observed_net_machine_seconds": None,
        "scenario_workload_rounds": scenario_rounds,
        "scenario_net_machine_seconds": net_s,
        "scenario_net_status": (
            "NOT_EVALUATED" if net_s is None else
            "HYPOTHETICAL_POSITIVE" if net_s > 0 else "HYPOTHETICAL_NEGATIVE"
        ),
        "realized_operational_roi": "UNVERIFIED",
        "provider_calls": data["provider_calls"],
        "provider_cost_usd": 0 if data["provider_calls"] == 0 else None,
        "github_actions_cost_usd": None,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("results", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--scenario-rounds", type=int,
                        help="unverified workload scenario; never counts as observed ROI")
    args = parser.parse_args()
    result = evaluate(json.loads(args.results.read_text()), scenario_rounds=args.scenario_rounds)
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
