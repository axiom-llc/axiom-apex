"""Matched offline scheduling trials; synthetic I/O, no model or external tools."""
import argparse
import asyncio
import hashlib
import json
import math
import platform
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path
from time import perf_counter_ns, process_time_ns

from team import Task, Worker, coordinate


async def agent(task, inputs, feedback):
    if task.delay:
        await asyncio.sleep(task.delay)
    return task.value + sum(inputs.values())


def oracle(tasks):
    # These workload manifests are deliberately in topological order.
    expected = {}
    for task in tasks:
        expected[task.id] = task.value + sum(expected[d] for d in task.deps)
    return expected


async def trial(tasks, workers, policy):
    expected = oracle(tasks)
    def validate(task, result):
        return None if type(result) is int and result == expected[task.id] else "wrong answer"
    if policy == "direct":
        values = {}
        for task in tasks:
            result = await agent(task, {d: values[d] for d in task.deps}, None)
            if validate(task, result) is not None:
                raise AssertionError("direct result invalid")
            values[task.id] = result
        return values == expected
    report = await coordinate(tasks, workers, validate, policy=policy)
    return report.results == expected and all(s == "accepted" for s in report.states.values())


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repeats", type=int, default=30)
    parser.add_argument("--output", type=Path, default=Path("results.json"))
    args = parser.parse_args()
    if not 2 <= args.repeats <= 1000:
        parser.error("repeats must be 2..1000")
    workloads = {
        "balanced": [Task(str(i), value=i, delay=.01) for i in range(8)],
        "skewed": [Task(str(i), value=i, delay=d) for i, d in enumerate(
            [.04, .002, .002, .002, .02, .02, .02, .02])],
        "diamond": [Task("root", value=1, delay=.005),
            *[Task(f"branch{i}", deps=("root",), value=i, delay=.01) for i in range(4)],
            Task("merge", deps=tuple(f"branch{i}" for i in range(4)), delay=.005)],
        "chain": [Task(str(i), deps=(str(i-1),) if i else (), value=1, delay=.005)
                  for i in range(8)],
        "noop64": [Task(str(i), value=i) for i in range(64)],
    }
    raw = []
    def measure(name, tasks, count, policy, repeat):
        workers = [Worker(f"w{i}", agent) for i in range(count)]
        cpu_start, start = process_time_ns(), perf_counter_ns()
        correct = asyncio.run(trial(tasks, workers, policy))
        elapsed, cpu = perf_counter_ns() - start, process_time_ns() - cpu_start
        raw.append(dict(workload=name, workers=count, policy=policy, repeat=repeat,
                        wall_ns=elapsed, cpu_ns=cpu, correct=correct,
                        input_tokens=None, output_tokens=None, cost_usd=None))
        if not correct:
            raise AssertionError("incorrect trial")
    policies = ["direct", "serial", "batch", "dynamic"]
    # Warm every case once, outside measured trials. Rotate order to reduce bias.
    for tasks in workloads.values():
        for policy in policies:
            asyncio.run(trial(tasks, [Worker(f"w{i}", agent) for i in range(4)], policy))
    for repeat in range(args.repeats):
        for name, tasks in workloads.items():
            for policy in policies[repeat % 4:] + policies[:repeat % 4]:
                measure(name, tasks, 4, policy, repeat)
        scaling = [Task(str(i), value=i, delay=.005) for i in range(16)]
        counts = [1, 2, 4, 8]
        for count in counts[repeat % 4:] + counts[:repeat % 4]:
            measure("scaling16", scaling, count, "dynamic", repeat)
    summary = []
    keys = sorted({(r["workload"], r["workers"], r["policy"]) for r in raw})
    for name, count, policy in keys:
        rows = [r for r in raw if (r["workload"], r["workers"], r["policy"]) == (name, count, policy)]
        walls = [r["wall_ns"] / 1e6 for r in rows]
        summary.append(dict(workload=name, workers=count, policy=policy,
            samples=len(rows), correct=sum(r["correct"] for r in rows),
            p50_ms=statistics.median(walls), p95_ms=percentile(walls, .95),
            p50_cpu_ms=statistics.median(r["cpu_ns"] / 1e6 for r in rows)))
    hashes = {p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
              for p in ("team.py", "test_team.py", "benchmark.py")}
    output = dict(schema="apex-team-evaluation/v1", generated_at=datetime.now(timezone.utc).isoformat(),
        source_base="203d4ceebc9b62f13e793e469dc2e87760c9b16e",
        environment=dict(python=sys.version, platform=platform.platform(),
                         clock="perf_counter_ns; complete asyncio.run per trial"),
        scope="Synthetic cooperative async I/O. No actual APEX subprocesses, providers, billing or durable recovery.",
        baselines="direct: sequential callback; serial/batch/dynamic: same prototype with different scheduling policies",
        percentile="nearest-rank p95; median p50; no inferential confidence intervals",
        repeats=args.repeats, code_sha256=hashes, summary=summary, raw=raw)
    args.output.write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps(dict(trials=len(raw), all_correct=all(r["correct"] for r in raw),
                          summary=summary), indent=2))


if __name__ == "__main__":
    main()
