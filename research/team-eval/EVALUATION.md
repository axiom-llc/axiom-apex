# Evaluation results

Recorded: 2026-11-05T03:28:29.330300+00:00

17 regression tests passed; compilation passed. All 720 measured scheduling trials passed their arithmetic oracle. Thirty samples per configuration. Exact code hashes and raw trials are retained in results.json.

## Measured synthetic latency

| Workload | Direct sequential p50 ms | Fixed batch p50 ms | Dynamic p50 / p95 ms | Direct / dynamic | Batch / dynamic |
|---|---:|---:|---:|---:|---:|
| balanced | 81.688 | 21.167 | 21.043 / 21.838 | 3.88x | 1.01x |
| skewed | 127.839 | 61.515 | 43.592 / 44.017 | 2.93x | 1.41x |
| diamond | 51.317 | 21.270 | 21.180 / 22.200 | 2.42x | 1.00x |
| chain | 41.367 | 42.297 | 42.191 / 43.850 | 0.98x | 1.00x |
| noop64 | 0.137 | 2.091 | 2.120 / 4.158 | 0.06x | 0.99x |

Ratios are ratios of sample medians, not paired mean speedups or confidence intervals. A ratio below 1 means dynamic was slower. These baselines run fixture callbacks, not actual APEX subprocesses or a single language-model agent.

## Synthetic scaling

| Workers | p50 / p95 ms | Speedup against one worker | Parallel efficiency |
|---:|---:|---:|---:|
| 1 | 83.983 / 85.539 | 1.00x | 100.0% |
| 2 | 42.498 / 43.173 | 1.98x | 98.8% |
| 4 | 21.582 / 22.678 | 3.89x | 97.3% |
| 8 | 11.123 / 11.580 | 7.55x | 94.4% |

Sixteen equal independent tasks, each awaiting a five-millisecond synthetic delay. This measures asynchronous waiting overlap, not CPU scalability.

## Interpretation and decision

- Uneven independent tasks show the clearest extra benefit from replacing fixed batches with slot refilling. Balanced tasks already exploit parallelism under batching; tiny differences there should be treated as noise.
- A diamond graph demonstrates accepted-result handoffs and parallel branches. A strict chain has no parallel slack and exposes coordination overhead.
- Immediate callbacks are substantially slower with coordination than direct sequential execution. Prefer the direct route for trivial work; no adaptive route selector is implemented.
- Latency includes event-loop creation, graph validation, callbacks, result validation, copies and coordinator work. Raw records also include process CPU time. Fixture sleeps dominate I/O cases.
- Tokens, provider costs and semantic model correctness are unmeasured (null in raw trials). No provider calls were made. No production speedup or quality claim follows from these results.
- This prototype demonstrates bounded operational autonomy, structured collaboration and automatic slot allocation. Intelligent reasoning remains an agent-adapter responsibility and has not been evaluated.
- Retain for future evaluation. Do not promote until the actual APEX adapter, crash-window recovery, provider quota/cost admission and representative application correctness gates in DESIGN.md pass.

## Reproduction

```bash
python -m unittest discover -v
python -m compileall -q team.py test_team.py benchmark.py
python benchmark.py --repeats 30 --output results.json
```

Python/platform/clock metadata and SHA-256 of the three executable/test files appear in results.json. Re-running changes timing and timestamps; compare correctness and distributions rather than expecting byte-identical measurements.
