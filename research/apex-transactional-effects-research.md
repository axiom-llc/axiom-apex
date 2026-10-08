# APEX Transactional Effects Research

**Project:** AXIOM APEX / ASON
**Status:** Source-grounded research and architecture proposal
**Scope:** Durable effect tracking, crash recovery, compensation, replay, and policy/execution boundaries
**Date:** 2026-09-11

## 1. Purpose

Record the validated failure modes and design constraints for adding transactional effect handling to APEX without overstating rollback guarantees or inventing capabilities absent from the inspected source.

This artifact separates:

- **observed findings** from the inspected repository snapshots;
- **required invariants** derived from those findings;
- **proposed saga/WAL architecture** that has not yet been implemented or validated.

## 2. Provenance

The research artifact from which these findings were derived inspected repository snapshots identified as:

- APEX: `57f381eb...`
- ASON: `78bed1e...`
- AXIOM Research: `7d145a...`

Treat those identifiers as provenance for the findings below. The live repositories may have changed after those snapshots; revalidate source locations before implementation.

## 3. Validated Findings

### 3.1 Run history is not a durable pre-effect journal

The inspected APEX execution path persisted run history as an end-of-run operation rather than durably recording the run and each external effect before execution.

Consequently, there is a crash window of the form:

```text
execute external effect
→ process terminates before final run-history write
→ durable history contains no authoritative record of that effect
```

This is the central transactional failure. A history database written only after the run completes cannot serve as a write-ahead log.

### 3.2 Existing rollback documentation overstated source reality

The inspected documentation described a transactional rollback architecture containing components that were not present in the inspected source, including references such as:

- `apex/core/rollback.py`;
- blast-radius rollback policy machinery;
- rollback schema/validator components.

Those claims must not be treated as implemented behavior merely because they appeared in documentation.

### 3.3 ASON rollback support was not an active transactional path

The inspected ASON rollback/reversal helper was not wired as a general automatic transaction manager. Its exercised behavior was limited, and at least one reversal target referenced a tool behavior inconsistent with the live APEX tool surface.

An optional reversal-plan helper is therefore not evidence of automatic rollback.

### 3.4 `rollback_on_failure` was not sufficient evidence of enforcement

The inspected policy surface included rollback-related configuration, but the research did not find an execution path that made it a reliable automatic transactional guarantee.

Configuration fields without a durable effect protocol do not close crash gaps.

### 3.5 Live replay can duplicate irreversible effects

The inspected live replay path could rerun execution from step 0. Without a durable per-step effect ledger and replay-aware idempotency rules, replay can repeat external actions that already succeeded before failure.

Therefore replay must distinguish at least:

- never attempted;
- planned but not started;
- started with outcome unknown;
- succeeded;
- failed without effect;
- compensated;
- compensation outcome unknown.

### 3.6 Tool retries require explicit effect safety classification

Retries are safe only when the tool contract establishes that repeating the operation cannot produce an unintended additional effect, or when the provider supports a verified idempotency mechanism.

A generic retry loop over side-effecting tools is not transaction safety.

## 4. Terminology

Use **transactional effects** carefully. For heterogeneous external tools, the appropriate model is usually a **saga with durable effect journaling and compensations**, not an ACID transaction spanning all providers.

Definitions:

- **Effect:** externally observable state change caused by a tool call.
- **Write-ahead record:** durable record written before the effect is permitted to execute.
- **Compensation:** a separately executed action intended to counteract a prior effect.
- **Reversible:** an effect for which a validated compensation can restore the relevant prior state under defined preconditions.
- **Irreversible:** an effect for which no reliable compensation is available.
- **Unknown:** the system cannot prove whether the effect occurred, typically because execution was interrupted after dispatch but before durable outcome recording.

## 5. Core Requirement

Persist the run and the intended effect transition **before** executing any side-effecting tool.

A correct durable order must resemble:

```text
create run record
→ persist complete expected plan/step cardinality
→ persist step/effect intent
→ durably mark dispatch boundary
→ invoke tool
→ persist observed result
→ advance run state
```

If the process can perform an effect before the corresponding run/effect record exists durably, the original crash gap remains.

## 6. Proposed Saga-Lite WAL

### 6.1 Run record

Before the first side effect, persist a run record containing enough immutable execution identity to recover safely, including:

- run ID;
- exact approved plan identity or digest;
- expected step count;
- policy/approval context required for audit;
- initial run status;
- creation timestamp if timestamps are part of the existing schema.

The expected step count must be durable. Recovery cannot infer completion reliably from whatever subset of step rows happened to survive.

### 6.2 Effect record

For every effectful step, persist an effect record before invocation. A minimal conceptual schema is:

```text
effect_id
run_id
step_index
tool_name
canonical_args_or_digest
effect_class
state
preimage_reference_or_data
idempotency_key_if_provider_supported
result_reference_or_digest
compensation_spec_if_supported
```

The exact persisted representation must follow the repository's existing storage conventions rather than introducing a parallel database without need.

### 6.3 Effect states

Avoid ambiguous state names unless their crash semantics are explicit.

A useful conceptual state machine is:

```text
INTENT_RECORDED
→ DISPATCHING
→ SUCCEEDED
→ FAILED_NO_EFFECT
→ COMPENSATION_INTENT
→ COMPENSATING
→ COMPENSATED
```

A process crash can leave `DISPATCHING` or `COMPENSATING` with an **unknown real-world outcome**. Recovery must represent that ambiguity instead of silently choosing success or failure.

If the implementation cannot distinguish `INTENT_RECORDED` from "provider request may have escaped," it must not claim exactly-once execution.

## 7. Effect Classification

Default tool effects to **unknown/irreversible** unless the tool contract proves stronger semantics.

A minimal classification model:

```text
PURE
RETRY_SAFE
REVERSIBLE
IRREVERSIBLE
UNKNOWN
```

Possible early candidates identified by prior research:

- `write_file`: potentially reversible only when a preimage is durably captured and later restoration cannot overwrite unrelated concurrent changes;
- `memory_write`: potentially reversible only when the previous value/version is captured and restoration semantics are version-safe.

Do not classify a tool as reversible merely because an opposite-looking command exists.

## 8. Compensation Correctness

### 8.1 Preimages are required for restorative compensation

A compensation such as "delete the file" is not a valid inverse for overwriting an existing file. Correct restoration requires the previous contents and relevant metadata or a stronger versioning primitive.

Similarly, restoring memory requires the prior value/version, not merely deleting the new value.

### 8.2 Concurrent external changes create clobber risk

Even with a preimage, blind restoration can destroy a legitimate change made after the original APEX effect.

Therefore reversible tools need a concurrency condition such as:

- compare-and-swap/version check;
- content digest check;
- provider revision identifier;
- exclusive ownership guarantee for the affected resource.

If that condition fails, compensation must stop and report unresolved manual recovery rather than overwrite newer state.

### 8.3 Compensation is itself an effect

Compensation must use the same durable discipline as forward effects:

```text
persist compensation intent
→ dispatch compensation
→ persist result
```

A crash during compensation is otherwise another ambiguous side-effect window.

Compensation must either be idempotent/retry-safe under a verified contract or expose an explicit unknown state requiring reconciliation.

## 9. Idempotency

An internal UUID does not make a provider operation idempotent.

An idempotency key is useful only when:

1. the external provider/tool explicitly accepts it or the local resource semantics enforce equivalent deduplication;
2. retries reuse the same durable key;
3. the exact operation identity covered by the key is defined.

Do not conflate **effect identity** with **provider-enforced idempotency**.

## 10. Recovery Rules

On startup or explicit recovery, classify incomplete effects conservatively.

### 10.1 Intent recorded, not dispatched

If the system can prove the provider call was never dispatched, the step may be safely attempted according to normal policy.

### 10.2 Dispatch outcome unknown

If a crash occurred after dispatch could have begun but before a result was durably recorded:

- query provider/resource state when a trustworthy reconciliation API exists;
- otherwise mark the effect `UNKNOWN`;
- do not automatically retry an irreversible/unknown effect;
- require policy-defined or human resolution where necessary.

### 10.3 Forward effect succeeded, later step failed

If policy requires compensation and the succeeded effect is validly reversible:

1. persist compensation intent;
2. execute compensation under its concurrency preconditions;
3. persist compensation outcome;
4. continue compensating prior reversible effects in reverse order only where policy permits.

Do not imply that successfully compensated heterogeneous effects are equivalent to a database rollback.

## 11. Replay Semantics

Replace "live replay from step 0" with ledger-aware behavior.

Replay/recovery must decide each step from durable state:

- `SUCCEEDED`: do not repeat unless the user explicitly requests a new run;
- `FAILED_NO_EFFECT`: may retry only if normal policy allows;
- `INTENT_RECORDED` with proven no dispatch: may execute;
- `DISPATCHING`/unknown: reconcile, do not blindly retry;
- `COMPENSATED`: do not replay the forward effect as part of recovery;
- irreversible succeeded effects remain historical facts.

A replay command intended only for deterministic inspection should remain non-effecting by default.

## 12. ASON ↔ APEX Boundary

The broader architecture assigns policy/blast-radius authority to ASON and deterministic execution authority to APEX.

Transactional behavior must preserve that separation:

- ASON decides whether a plan/effect set is policy-approved and whether compensation is permitted or required.
- APEX executes the **exact approved plan** and durably records effect state.
- APEX must not reinterpret the plan through a probabilistic planner during recovery.
- Recovery must not silently expand authority beyond the original approval.

The exact ASON→APEX plan submission contract should be verified against the current repositories before implementing the WAL, because transactional semantics depend on knowing which component owns the authoritative plan.

## 13. Required Invariants

A production implementation should preserve at least:

1. **Run-before-effect:** a durable run exists before any external effect.
2. **Intent-before-dispatch:** durable effect intent exists before dispatch begins.
3. **Durable plan cardinality:** recovery knows the approved expected step set/count.
4. **No blind replay:** succeeded or outcome-unknown effects are not automatically repeated.
5. **Conservative default:** unclassified tools are `UNKNOWN` or `IRREVERSIBLE`.
6. **Compensation is journaled:** compensations obey the same crash-discipline as forward effects.
7. **Preimage/version safety:** restorative compensation cannot silently clobber newer external state.
8. **Provider idempotency is explicit:** internal IDs are not treated as external idempotency guarantees.
9. **Policy authority is preserved:** recovery/compensation cannot exceed the approved plan/policy envelope.
10. **Audit truthfulness:** logs distinguish known success/failure from ambiguous real-world outcome.

## 14. Validation Plan

### 14.1 Deterministic crash injection

Inject process termination around every state boundary for each effect class:

```text
before run record
immediately after run record
before effect intent
immediately after effect intent
before provider dispatch
immediately after provider dispatch begins
before success persistence
immediately after success persistence
before compensation intent
immediately after compensation intent
while compensation is executing
before compensation result persistence
```

After restart, assert that recovery never silently repeats an irreversible/unknown effect.

### 14.2 Reversible tool tests

For any tool promoted to `REVERSIBLE`, test:

- creation of a new resource;
- overwrite of an existing resource;
- preimage persistence;
- successful compensation;
- concurrent external modification before compensation;
- crash during compensation;
- repeated recovery invocation.

### 14.3 Replay tests

Assert that live recovery/replay:

- skips durable successes;
- does not retry unknown dispatches without reconciliation;
- preserves irreversible effects as completed history;
- does not regenerate or reinterpret the originally approved plan.

### 14.4 Storage tests

Verify ordering and durability properties of the actual history/WAL storage implementation. A state-machine design is insufficient if database transaction boundaries do not preserve the required order under process termination.

## 15. Open Risks and Unresolved Questions

The prior research identified the following issues that must remain explicit until resolved:

1. **Dispatch ambiguity:** a state named `executing` or `planned` is insufficient unless its exact crash boundary is defined.
2. **Compensation ambiguity:** a crash during compensation can leave real-world state unknown.
3. **Concurrent mutation:** preimage restore can clobber independent changes without version checks.
4. **Provider limitations:** many tools cannot expose outcome reconciliation or true idempotency.
5. **Completion detection:** expected step count/identity must be durable before effects begin.
6. **Semantic change under failure:** adding compensations changes failure behavior and must be treated as an explicit execution contract, not hidden cleanup.
7. **Current source drift:** implementation work must revalidate the findings against current APEX/ASON before changing code.

## 16. Minimal Implementation Sequence

Do not implement broad rollback first. Use this order:

1. Verify the current ASON→APEX authoritative-plan boundary.
2. Persist a run row and expected plan identity/count before effects.
3. Add per-step/effect WAL states with conservative effect classification.
4. Make replay/recovery ledger-aware and disable blind re-execution of ambiguous effects.
5. Add crash-injection tests for irreversible/unknown effects.
6. Implement one reversible local tool only after durable preimage and concurrency-safe restore semantics are defined.
7. Journal compensation itself and test crashes during compensation.
8. Expand reversible coverage tool-by-tool only with verified contracts.
9. Update documentation to match only behavior demonstrated by tests.

## 17. Decision

Adopt a **saga-lite durable effect ledger** rather than claiming general transactional rollback.

The first production milestone is not automatic rollback. It is closing the crash gap by ensuring that every effect has a durable pre-dispatch record and that recovery never blindly repeats an effect whose real-world outcome is unknown.

Only add compensation where the tool-specific inverse, preimage requirements, concurrency conditions, and crash behavior are all explicitly defined and tested.
