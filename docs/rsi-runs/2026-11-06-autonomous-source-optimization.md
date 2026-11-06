# Bounded APEX RSI acceptance — 2026-11-06

## Disposition

**ACCEPTED: isolated, source-derived optimization capability and reproducible lab improvements.**
**NOT VERIFIED: realized net operational ROI, open-ended autonomous RSI, LLM-generated closed loop.**

The implementation and evidence contract were merged to APEX `main` in
[`4bfd6a886a002a0729fb92956af69b21913560b1`](https://github.com/axiom-llc/axiom-apex/commit/4bfd6a886a002a0729fb92956af69b21913560b1)
([PR #6](https://github.com/axiom-llc/axiom-apex/pull/6)).
The automatically generated code-optimization candidates were deliberately
**not pushed or merged to main**. A green fixed-workload benchmark is insufficient
to establish net benefit for an unobserved production call volume.

## Frozen workload and acceptance

- Candidate source scope: `apex/core/planner.py` (within the existing APEX patch allowlist). Generator, kernel safety, benchmarks, tests, and evaluator cannot be modified by candidates.
- Generator: deterministic source-pattern recognition, deriving Git unified diffs; not an LLM. Two eligible transformations are cached JSON decoding and hoisted type-name dictionary creation.
- Dataset: fixed Python runtime microbenchmark, 4,000 plan-JSON extraction/output-normalization cases plus 15,000 schema type-name descriptions per round. Nine timed rounds per benchmark subprocess. Training and holdout use disjoint offset-based values.
- Each baseline and candidate is measured with three independent subprocess samples in the same Bubblewrap + cgroup-v2 boundary; holdout is applied to the actual candidate scratch worktree after native regression tests.
- Admission requires a real regression pass, valid nonmock finite measurements, p50 improvement of at least 1 ms **and** 2%, p95 regression no greater than 10%, CPU regression no greater than 5%, peak RSS increase no greater than 10%, and unchanged workload units. Failed candidates are ineligible.
- Accepted candidates become unique, cumulative, local Git commits; one generation inherits the previously accepted source. The controller stops when no applicable rule/candidate remains. CI has `contents: read`; no candidate is pushed or merged by the runner.

## Four independently executed CI trials

Numbers are median timed values in milliseconds, except peak resident memory in KiB and wall overhead in seconds. Each row reflects its own baseline and final accepted generation on one GitHub-hosted runner.

| Native CI run | Holdout p50 baseline → final | p50 reduction | Holdout p95 baseline → final | CPU baseline → final | Peak RSS baseline → final | RSI evaluation | Full CI wall |
| --- | --- | ---: | --- | --- | --- | ---: | ---: |
| [42161735063](https://github.com/axiom-llc/axiom-apex/actions/runs/42161735063) | 63.563 → 50.959 | 19.83% | 65.325 → 51.533 | 63.557 → 50.959 | 22696 → 22696 | 57.856 s | 181 s |
| [42162166532](https://github.com/axiom-llc/axiom-apex/actions/runs/42162166532) | 63.246 → 51.650 | 18.34% | 64.493 → 52.585 | 63.240 → 51.641 | 22748 → 22764 | 57.436 s | 172 s |
| [42162178847](https://github.com/axiom-llc/axiom-apex/actions/runs/42162178847) | 55.934 → 46.937 | 16.09% | 56.483 → 47.101 | 55.930 → 46.939 | 22684 → 22732 | 52.954 s | 176 s |
| [42162305690](https://github.com/axiom-llc/axiom-apex/actions/runs/42162305690) | 34.146 → 27.566 | 19.27% | 34.742 → 28.456 | 34.149 → 27.567 | 22736 → 22636 | 38.083 s | 125 s |

**All four runs:** three candidates generated and tested; two cumulative lab-accepted generations; stop `CONVERGED_NO_CANDIDATES`. All four runs passed APEX CI (206 full tests, two deselected; 29 focused RSI tests) and the separate 51-test isolation job (one deselected). Each contains the full per-generation evidence and, in later runs, per-candidate patch digest and decision provenance.

Retained run artifacts:
- [42161735063 / artifact 13476603725](https://github.com/axiom-llc/axiom-apex/actions/runs/42161735063/artifacts/13476603725)
- [42162166532 / artifact 13477044062](https://github.com/axiom-llc/axiom-apex/actions/runs/42162166532/artifacts/13477044062)
- [42162178847 / artifact 13477571687](https://github.com/axiom-llc/axiom-apex/actions/runs/42162178847/artifacts/13477571687)
- [42162305690 / artifact 13477621507](https://github.com/axiom-llc/axiom-apex/actions/runs/42162305690/artifacts/13477621507)

## Machine-time and ROI accounting

The median **within-run** p50 reduction across these independent CI trials was 18.80%. Median absolute savings were 10.297 ms per fixed 19,000-operation benchmark round. Across four trials:

- RSI controller wall time: **206.329 s**, including candidate tests, benchmark subprocesses and unsuccessful evaluations.
- End-to-end GitHub Actions run wall time: **654 s** (sum of each run's start-to-completion wall, including setup and independent CI; not the exact billed runner minutes).
- Equivalent break-even volume charging RSI controller wall time alone: **380,722,000 fixed benchmark operations**.
- Equivalent break-even volume charging full CI run wall time: **1,206,766,000 fixed benchmark operations**.
- Provider calls and provider-token expense in rule mode: **zero**; GitHub Actions cash expense **unavailable**, not assumed zero. Agent analysis/development overhead is not independently priced.
- Actual APEX production workload volume, frequency, business value, external model costs and client-validated savings: **not measured**. Thus realized net operational benefit cannot be certified.

These break-even values use the median observed per-round saving to estimate work needed to amortize the observed experiment overhead, **not evidence that these workloads occur in production**. Independent acceptance on heldout input values does not establish transfer to real agents or customer workloads.

## Reproduction

On a Linux CI runner with Python 3.12, Git, Bubblewrap and delegated systemd cgroup-v2 controllers (see [isolation setup](../rsi.md)), check out the exact APEX implementation revision. Use a clean, named local branch with a configured test-only Git identity. Install APEX development dependencies, then execute:

~~~bash
python -m pytest tests/test_rsi.py tests/test_rsi_autonomous.py -q
python -m pytest tests -m 'not integration' -q
python -m apex rsi --generator rules --cycles 4 --budget-tokens 200000 > /tmp/rsi-lab.json
python -m apex.rsi_lab_evidence /tmp/rsi-lab.json --output /tmp/rsi-roi.json
~~~

Exact hosted CI command/configuration is in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml); execution starts only on RSI-scoped PRs. CI retains JSON run receipts for 90 days, while this source-revision-bound summary persists in Git.

## Acceptance limits and next independent gate

The source rule search terminates at a **fixed point of its two eligible transformations**, not mathematical convergence of arbitrary future candidate code. A second-level model that invents new beneficial transformation rules, independently evaluates them, measures sustained production benefits, learns from failures, and safely applies improvements is not demonstrated.

Do not promote lab-selected runtime optimization commits to production solely because these benchmark tests passed. The next decision requires independently observed representative APEX call volume and externally fixed acceptance, measured p50/p95/CPU/RSS under the real operator workload, an explicit horizon for amortizing total evaluation overhead, and verified positive net machine-time after regression and cash costs. Only then can source optimization be approved as **net operational benefit** rather than a reproducible laboratory speedup.

## Independent reconstruction and actual fixed point on optimized source

The source-only reconstruction of both selected planner transformations is
[review-only PR #7](https://github.com/axiom-llc/axiom-apex/pull/7);
its two cumulative commits are `5660410cba524037880fb96d19114b1a0b227ff3`
and `8e3026684b2702983c4d651b3f133d6d271f75ca`.
These are separately reconstructed review commits, not the ephemeral original
CI local commits. The [PR CI run
42162840230](https://github.com/axiom-llc/axiom-apex/actions/runs/42162840230)
passed 206 offline tests, 29 focused tests and 51 isolation tests. Running
the actual source-derived optimizer against this already-optimized checkout
produced **zero generated candidates, zero accepted, and
`CONVERGED_NO_CANDIDATES`** in 0.007 s. The source PR remains unmerged:
operator-workload ROI and independent production acceptance are not established.

## Fail-closed ROI provenance correction

The [ROI provenance hardening PR #8](https://github.com/axiom-llc/axiom-apex/pull/8)
merged as `08fde4e99090ac9059ebcf32c916c9a159116233`.
A former optional caller-supplied workload count could be mislabeled
`MEASURED_NET_POSITIVE` despite having no independent origin.
It now accepts **scenario** rounds only, reports hypothetical
scenario arithmetic separately, and always retains
`observed_real_workload_rounds = null` and
`realized_operational_roi = UNVERIFIED`. Native APEX CI passed
206 tests, 29 focused tests and 51 isolation tests on the correction.
No caller-supplied scenario is evidence of actual production benefit.
