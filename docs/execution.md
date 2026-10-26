# APEX execution

[← Project overview](../README.md) · Commands below run from the repository root.

## Planning and execution

Limit generated plans to 32 total steps. Require a non-empty goal, validate every tool name and argument against the active registry, reject unknown or missing arguments and incompatible argument types, and require exactly one final halt step.

Build planner tool documentation from the active registry so built-in, memory, user-defined, and MCP tools use the same runtime schema.

Enforce a 300-second timeout per tool call, retry failures up to three times only for tools explicitly marked `retry_safe=True` (built-in file/memory reads and HTTP GET), reject non-JSON-serializable tool output, and reject serialized tool output above 10 MiB.

Record the complete validated plan before execution mutates runtime state. Persist each run and its tool events atomically in `APEX_HISTORY_DB_PATH` with SQLite WAL enabled.

## Safety

Use `--audit` to run deterministic checks and an LLM plan audit before execution. Treat this audit as an advisory pre-execution safeguard, not a complete policy boundary.

Allow `write_file` targets only under the current home directory or `/tmp` in audit mode. Match resolved path boundaries rather than string prefixes.

Trusted application code must enforce caller-selected policy through `axiom-ason` and prevent direct APEX bypass. Neither this integration nor APEX provides automatic transactional rollback; file compensation remains disabled fail-closed.

## Replay

Use recorded plans directly; do not ask the planner to regenerate a live replay.

```bash
apex replay 42 --mode simulate
apex replay 42 --mode dry
apex replay 42 --mode live --diff
apex replay 42 --mode live --no-write
```

Use `simulate` to print recorded tool events without executing anything. Use `dry` to print the recorded plan. Use `live` to validate the entire recorded plan against the current registry and recover that same run from its durable effect ledger. Completed steps return their recorded results; they do not execute again. Use `--diff` to compare recovery results (including retained successes) with recorded results. Use `--no-write` to reject plans requiring `write_file`.

Before tool execution, APEX commits the existing run ID, the complete accepted execution plan, a SHA-256 digest of its canonical JSON, its step count (including halt), a SHA-256 digest of the planner-visible tool-registry contract, and one `INTENT_RECORDED` row per tool call in the history SQLite database. The registry digest covers registry key/name, input/output type schemas, required arguments, and `retry_safe`; registry ordering and effect implementation identity are intentionally excluded. For `POST /authorized-run`, the same transaction also commits the ASON authorization identity, matching approved-plan digest, policy digest/reference, authority reference, and accepted decision. Authorization/plan/registry-contract mismatch fails before dispatch. Every tool call is conservatively journaled, including custom and MCP tools.

A committed `DISPATCHING` transition precedes entry into tool code. The normalized result and history event are committed together afterward. Recovery uses these states:

| Durable state | Live recovery behavior |
| --- | --- |
| `INTENT_RECORDED` | Dispatch has not begun; execution may continue after complete plan validation. |
| `DISPATCHING` | Dispatch may have occurred; block the run without retrying. |
| `SUCCEEDED` | Reuse the recorded result without dispatch. This means the tool returned acceptable JSON, not that a remote business operation necessarily succeeded. |
| `FAILED_UNKNOWN` | An exception, timeout, or invalid output was observed; block because an effect may still have occurred. |

Any uncertain step blocks all further dispatch for that recovery. Existing bounded retries remain available only for tools explicitly marked `retry_safe`, during the original uninterrupted execution. Observed retry errors are saved before retrying; a restart never resumes an ambiguous retry loop. The plan binding is checked before recovery; authorized runs additionally re-check the durable authorization against that plan digest. Tool arguments are copied before dispatch so tool mutation cannot change the bound plan. No planner or policy audit is rerun during recovery.

`GET /runs/<id>` exposes the ledger identity and effect states. Incomplete runs can be found through history even when a crash prevented the initial HTTP response; their `exit_code` remains null until execution finishes. Live replay of old history records or dry-run records without a ledger is blocked. Dry and simulate inspection remain available. Explicitly submitting a plan again creates a new run and can repeat effects; HTTP submission is not deduplicated.

Tests cover abrupt process termination before and after SQLite commits and tool effects. This does not establish host-power-loss atomicity or exactly-once external effects. There is no automatic reconciliation, compensation, or multi-process recovery coordination. Keep recovery under the existing single-executor operational model and retain the same trusted tool implementations/configuration. Live recovery now fails closed if the planner-visible tool-registry contract is missing or differs from the contract bound at run creation. This detects interface drift only; it does not pin tool implementation code, environment, provider state, or remote service semantics. Compensation requires an explicit approval contract plus tool-specific inverse, durable preimage, concurrency/version checks, and crash/reconciliation semantics before implementation.

