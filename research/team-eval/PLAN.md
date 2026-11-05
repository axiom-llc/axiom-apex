# Bounded-team evaluation implementation plan

Goal: retain a small executable experiment and evidence without production integration.
Architecture: single coordinator, fixed graph, typed callbacks, copied JSON handoffs,
validator feedback and capability-aware slot filling. Standard-library Python 3.11+.
Spec: DESIGN.md. Explicit user request authorizes this evaluation prototype.

## Constraints

Separate research branch only. No main mutation, package wiring, CI trigger,
provider call, spending, recursive delegation or durable-state claim.

## Review focus

Dependency cycles and duplicate identities must fail before dispatch; unknown
outcomes must not retry; rejected results must not reach dependents; concurrent
callbacks must not share mutable input objects; serial/tiny work must expose overhead.

## Tasks

- [x] Define Task, Worker, Report and coordinate interfaces; write regressions first.
- [x] Observe missing implementation failure; implement bounded graph execution.
- [x] Test instruction handoff and size limits before adding instruction support.
- [x] Verify graph validation, slot reuse, role eligibility, feedback bounds,
  timeout/exception behavior, cancellation and input/result isolation.
- [x] Implement matched direct/serial/batch/dynamic benchmarks with golden outputs,
  raw trials, exact code hashes, CPU/wall latency, p50/p95 and 1/2/4/8-worker scaling.
- [x] Run the complete isolated suite and benchmark final code; document limits.
- Persistence protocol: use a separate research branch and independently read back
  every artifact before reporting successful retention.
- [ ] Future: actual APEX adapter, model/task evaluation, crash recovery and quota gates.
