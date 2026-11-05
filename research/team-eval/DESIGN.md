# Bounded agent teams: evaluation design

Status: isolated executable prototype, not production integration.
Source baseline: axiom-llc/axiom-apex@203d4ceebc9b62f13e793e469dc2e87760c9b16e.
Date: November 4, 2026 America/New_York.

## Decision

Use one coordinator, an immutable caller-supplied task graph, isolated worker
inputs, structured result handoffs, deterministic validation and ready-task
scheduling. Keep the existing APEX CLI, package, README, CI and runtime unchanged.
The experiment lives only on its evaluation branch under research/team-eval/.

This implements bounded operational autonomy: once given a graph, the coordinator
advances work without per-task intervention. It implements collaboration through
accepted dependency results and validator feedback. An agent callback can perform
specialized reasoning, but the included callbacks are deterministic fixtures.
Intelligent model reasoning and general autonomous problem decomposition have NOT
been demonstrated. Automatic balancing means filling available capable worker slots
as they become free, preferring higher caller-supplied speed hints among idle
eligible workers. There is no learned router, preemption or performance guarantee.

## Options and smallest viable choice

| Option | Benefit | Cost / disposition |
|---|---|---|
| Existing swarm with a ready queue | Better utilization for independent tasks | Cheapest; no dependency handoffs or validation feedback |
| One coordinator with a fixed dependency graph | Parallel progress plus bounded collaboration | Chosen; one process and standard library only |
| Peer messaging, mutable shared plans, distributed actors | More flexible interaction | Deferred: ordering, consensus, recovery and context costs lack evidence |

## Interfaces and authority

- Task: stable ID, instruction, dependencies, required capability, per-attempt
  timeout and explicit correction_safe flag. value/delay are synthetic workload
  fixture fields, not provider performance metadata.
- Worker: stable ID, capabilities, positive speed hint and async agent callback.
- Callback: agent(task, accepted_dependency_results, feedback) -> JSON value.
- Validator: validator(task, candidate) -> None for acceptance, or bounded textual
  feedback. A separate application validator must check substantive correctness;
  JSON shape, model agreement and hashes alone are insufficient.
- Report: task states, accepted results, attempt identities/status/duration and
  complete coordinator duration. No model/token/cost figures are fabricated.

Coordinator alone owns task-state transitions. Workers see only their own task,
copies of accepted dependency outputs and their own correction feedback. They
cannot submit new tasks, edit the graph, broadcast messages or grant authority.
Accepted outputs are copied before downstream handoff and before validation.

pending -> running -> accepted | rejected | unknown
Failed prerequisites propagate blocked to descendants. Unrelated tasks continue.
At most one correction is allowed after a rejected candidate, and ONLY when the
caller explicitly marks that task pure/repeat-safe. Timeout, callback exception
or validator exception becomes unknown and never triggers an automatic retry.
Partial results never release dependent work.

Limits: 1..64 tasks, 1..8 workers, one active attempt per worker, 64 KiB default
per instruction/input/output/feedback JSON payload, two attempts maximum per task
only under correction_safe. Finite timeouts default to five seconds per attempt.
The graph and resource compatibility are checked before any dispatch.

## Execution boundary and production integration proposal

The prototype uses trusted cooperative async callbacks in one cloud process.
It is NOT a sandbox. A synchronous/blocking callback or one that suppresses
cancellation can defeat cooperative timeouts. There are no real provider calls,
APEX subprocesses, filesystem mutation permissions, credential access, persistent
queue, crash recovery, billing enforcement, request/token quota enforcement,
multi-host scheduling or restart/resume behavior in this experiment. Caller speed
hints do not model rate limits or guarantee fair/global-optimal allocation.

Before real execution, the proposed adapter should launch isolated APEX subprocesses
for signal-based tool timeouts and bind task IDs to exact child run IDs. Keep
candidate files in disjoint directories and use one integration owner. Add process
termination, provider admission limits, authority checks and independent result
validation. Do not route arbitrary side effects through these cooperative fixtures.

Director remains strategy/authority owner. Harness remains task/lease/acceptance
owner. APEX remains exact-plan effect execution/recovery owner. A production
coordinator should orchestrate these interfaces, not create a competing durable
task database. Harness currently requires an expected result digest and hard-zero
cash ceiling: generated candidates need evidence-based acceptance in addition to
integrity hashes; paid-provider support requires a separately authorized change.
Do not silently relax these constraints. APEX unknown effects remain blocked even
if a task lease expires. Cross-store task/run binding needs crash-window tests.

## Performance and scalability evaluation

benchmark.py measures complete asyncio.run latency and process CPU time using
monotonic nanosecond clocks. It compares direct sequential callbacks against
serial, fixed-batch and dynamic policies in this SAME prototype. Fixed batching
is a scheduling proxy for the current swarm, not a measurement of actual APEX.
Direct baseline has less lifecycle machinery and is deliberately included to
expose overhead. Workers/callbacks/validators/workloads are otherwise matched.

Workloads: balanced independent tasks, skewed durations, a diamond dependency
graph, a strictly serial chain, 64 immediate callbacks and 16 tasks at worker
counts 1/2/4/8. Sleep durations simulate I/O waiting; these are not CPU workloads,
model latencies or application outputs. Every result is checked against a
precomputed independent arithmetic oracle. Thirty repetitions per configuration,
rotating policy order and warmup outside measurements; raw trials, p50, nearest-rank
p95, CPU times, environment and exact code hashes are retained in results.json.
No confidence intervals or significance claims; microsecond differences may be noise.

For parallel work, the ideal lower bound is max(total service work / workers,
critical-path service time), before coordination/provider overhead. Chains cannot
benefit from more workers. CPU-heavy Python needs processes; coroutine concurrency
does not bypass the GIL. Provider rate limits can flatten or reverse scaling.
The simple scheduler scans a bounded graph; it is suitable for this 64-task
experiment. It is not an evaluated large-graph or distributed scheduler. Eight-worker
synthetic scaling establishes only the measured asynchronous case.

## Future evaluation and promotion gate

1. Keep direct execution for short or serial work; use coordination only for a
   demonstrated dependency/context-isolation requirement.
2. Implement and separately test a subprocess/recorded-fixture adapter. Compare
   the actual existing swarm and a single agent on representative research and
   engineering tasks, preserving equivalent correctness and authority checks.
3. Add crash/restart, rate-limit, cancellation, conflicting artifacts, stale input,
   validator failure, credential boundary and duplicate-effect tests before any
   production integration. Test heterogeneous worker behavior under measured
   rather than asserted speed and shared provider quota constraints.
4. Under explicit provider/cost authorization, measure total input/output tokens,
   cache billing, cost per independently accepted task and p50/p95 end-to-end
   latency. Assess semantic quality with independent tests/rubrics, not agent votes.
5. Suggested gate: no correctness or recovery regression, plus >=20% lower latency
   at <=10% extra cost per accepted task on the target workload, OR lower cost at
   equivalent correctness. These thresholds are proposals, not measured guarantees.

Peer messaging, consensus, self-spawned teams, mutable plans, automatic retries of
uncertain effects, distributed coordination and production publication remain out
of scope. No change to public feature claims is authorized by this experiment.
