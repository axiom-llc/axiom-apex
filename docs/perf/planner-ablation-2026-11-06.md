# APEX planner computational performance acceptance — 2026-11-06

## Decision

**ACCEPT:** reuse one stateless JSON decoder and hoist the fixed type-name
lookup dictionary in `apex/core/planner.py`. Both are cumulative, behavior-
preserving source changes. No new runtime dependencies or provider API calls.

**Boundary:** this is a measured improvement in local planner processing,
not proof of faster external LLM completion, billed-token reduction, or
recovered owner labor.

## Reproducible paired experiment

- Source candidate: [PR #7](https://github.com/axiom-llc/axiom-apex/pull/7), measured implementation revision `07eed7d923bde148a01ceada39d91d3cb6ddedf7`.
- Pinned baseline commit `3d9109cf786b0b64a9eeaa2f4c2b2b59983d4ded`. The baseline planner source SHA-256 is `5aef53cbb1d4e292349400443e3260ac41da02f787f352b54310f9c3a804e721`. The optimized source SHA-256 is `13cdc31cf153c87a7f3bed8ab7ad5d4fbe75dedb75b831ff36a888da26404b23`.
- Script: [`benchmarks/planner_ablation.py`](../../benchmarks/planner_ablation.py) in this PR, using no additional installed dependencies.
- Four variants built from the exact same baseline: unchanged, cached decoder only, hoisted type lookup only, and both cumulatively. Each executes the real APEX `parse_plan`, `_describe_tool` and `render_prompt` functions, not replayed predetermined latency scores.
- 20 alternating, within-runner, pinned-input samples for each variant and each of two execution cohorts; 450 parser operations per round plus schema descriptions and optional complete prompt rendering. Wall time and process CPU measured separately.
- Correctness: 133 valid/invalid plan inputs, including valid JSON fences; all 94 successful plans and 39 rejected plans matched the baseline, as did tool descriptions, rendered prompts and 399 concurrent parsing calls per candidate variant.
- Gates: fixed-input equivalence, p50 improvement >=5% and >=1 ms scaled to 19,000 operations, p95 <=110% of baseline, median CPU <=105% of baseline, traced peak allocations <=110% of baseline, second-cohort p95 no regression above 10%. The type-name change additionally requires >=2% marginal gain after cached decoding.
- Native [APEX CI run #42165241080](https://github.com/axiom-llc/axiom-apex/actions/runs/42165241080) **PASS**: 206 offline tests passed (2 deselected), 29 focused RSI tests passed, 51 isolation tests passed (1 deselected), platform packages and distribution successful. Complete raw [GitHub artifact](https://github.com/axiom-llc/axiom-apex/actions/runs/42165241080/artifacts/13478976598), retained for 90 days.

## Measured results

Each value is a measured median or measured p95 in milliseconds unless stated.

| Mode | Planner p50 | Planner p95 | Planner CPU p50 | Complete prompt+parse p50 | Complete p95 | Traced peak allocation (bytes) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Original | 4.3030385 | 4.395610 | 4.3035705 | 12.445517 | 12.575258 | 5143 |
| Decoder only | 3.6055700 | 3.665550 | 3.6065740 | 11.531118 | 11.706127 | 2411 |
| Type lookup only | 4.1090070 | 4.164873 | 4.1095955 | 11.720134 | 11.925138 | 3864 |
| Combined | 3.4306875 | 3.701941 | 3.4314110 | 10.840821 | 11.112013 | 2291 |

- Combined planner p50: **20.27% faster** (0.872351 ms saved per fixed 450-operation round).
- Combined complete prompt rendering + parsing p50: **12.89% faster** (1.604696 ms saved per fixed round).
- Combined planner p95: **15.78% faster**; complete prompt/parse p95 **11.64% faster**.
- Decoder alone: **16.21% faster** planner p50, meeting the main >=5% materiality gate.
- Type lookup alone: **4.51% faster**, below the standalone 5% target; it is retained because **sequentially after decoder reuse** it removes another 0.174883 ms (4.85% relative to decoder), exceeding the independently specified >=2% marginal gate.
- Traced temporary peak allocations: 5143 -> 2291 bytes (55.45% lower). This metric covers benchmark-traced allocations; it is **not** a claim of 55% less process RSS or deployment memory.
- All output equivalence and CPU/latency/memory acceptance gates passed. Local correctness/regressions remained green.

## Overhead, resource efficiency, and net computational benefit

The ablation itself consumed **1.567 s** including mode compilation, warmup,
quality checks, both cohorts, and allocation measurement. At the observed
0.872351 ms batch speedup, evaluation amortizes after **1,796** repeated
450-operation batches (808,200 parser calls, plus accompanying tool descriptions), **conditional on comparable future
runtime workloads**.

The full GitHub Actions run wall time was **119 s** (04:54:30–04:56:29 UTC).
Conservatively allocating all of it to the optimization increases break-even
to **136,413** equivalent batches (61,385,850 parser calls, plus accompanying tool descriptions); this includes
regular existing regression/packaging/runner overhead and is not billed CI
usage. GitHub Actions cash billing was not available. Provider/model calls
added by this benchmark: zero. No external purchases or persistent workers
were authorized.

The source changes add two reusable module-level objects (a JSON decoder and a
dictionary), used without mutation by the planner; they remove repeated
per-call decoder and dictionary allocations. At runtime they require
no extra network calls, API quota, background scheduling, or configuration.
Measured performance gains persist per qualifying future invocation, but
actual production invocation volume, latency dominated by model calls,
operator active-time benefit and business monetary ROI remain unmeasured.

## Failure and correction trail

The initial [run #42165019214](https://github.com/axiom-llc/axiom-apex/actions/runs/42165019214)
failed the benchmark gate because its absolute 1 ms minimum was incorrectly
applied to 450 operations rather than scaled from the previous 19,000-operation
benchmark. That benchmark fixture also contained escaped rather than literal
code fences. Commit `07eed7d923bde148a01ceada39d91d3cb6ddedf7`
corrected both defects, added direct fenced-JSON acceptance and verified
sequential marginal improvement. The next native CI run passed every gate.
The failed run is retained as failure, not retroactively called successful.

## Convergence and limitations

This accepts the two measured candidate changes. Additional optimization
must present a fresh revision-pinned baseline and pass the same independent
acceptance thresholds. The bounded source-rule search earlier reached
`CONVERGED_NO_CANDIDATES` after these transformations, meaning **only that
its two available rules were exhausted**, not global software optimality.
This decision does not introduce an automation cadence or elevate production
ROI estimates into actual measurements.
