# axiom-apex

Execute bounded AI-agent tasks through explicit tool calls defined by schema-validated plans compiled from natural language, recording both fully for inspection and replay.

## Install

Python 3.11 or 3.12 is validated. Version 3.2.0 is **unreleased**; the latest published baseline is 3.1.1.
Current AXIOM distribution is prepared for [GitHub Releases](https://github.com/axiom-llc/axiom-apex/releases).
The legacy PyPI package does not provide this source architecture; do not use a
bare `pip install axiom-apex` to obtain it.

After the releases below are published, install the exact wheels in a fresh environment:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install \
  "axiom-rag @ https://github.com/axiom-llc/axiom-rag/releases/download/v1.5.0/axiom_rag-1.5.0-py3-none-any.whl" \
  "axiom-apex @ https://github.com/axiom-llc/axiom-apex/releases/download/v3.1.1/axiom_apex-3.1.1-py3-none-any.whl"
python -m pip check
```

Supply **both** wheels in the same command: APEX requires `axiom-rag>=1.5.0`,
and the old PyPI RAG cannot satisfy that contract. Release RAG first.

These versioned URLs are future release targets, not a claim that assets already exist.
See [release gates and checksum verification](RELEASE.md). Third-party dependencies
may still be downloaded from the public Python index; no AXIOM PyPI account is needed.

For development before publication, run from this checkout:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install ../axiom-rag -e '.[dev]'
```

Check out matching RAG 1.5.0 source alongside APEX. Install RAG as a regular
package so RSI candidates do not depend on access to its source checkout.
Set `GEMINI_API_KEY` only for provider work, or select configured local Ollama.

## Run

```bash
apex "write 'hello world' to /tmp/out.txt and read it back"
apex --dry-run "write hello to /tmp/out.txt"
apex --audit "..."
apex --trace "..."
apex --full-trace --trace-path /tmp/trace.jsonl "..."
apex --interactive
apex --version
```

Use the subcommands:

```bash
apex history [-n 20]
apex stats
apex export --format jsonl|csv [--since ISO] [--fields a,b,c] [--events] [-o path]
apex replay <run_id> --mode simulate|dry|live [--diff] [--no-write]
apex serve [--host 127.0.0.1] [--port 8080]
apex swarm --tasks tasks.json [--workers 4] [--human-loop] [--trace-path PATH]
apex rsi [--cycles 3] [--budget-tokens 50000] [--tasks PATH] [--mock-bench]
```

Run the task benchmark:

```bash
python -m apex.bench --tasks benchmarks/tasks.json --mock
python -m apex.bench --tasks benchmarks/tasks.json
```

Compute `apex_score = pass_rate × speed_factor × token_efficiency`. Keep each factor in the inclusive range `0.01..1.0`, except `pass_rate`, which may be `0.0`. Benchmark JSON also records a secret-free `apex/execution-profile-v1` object and SHA-256 `config_digest` binding the resolved provider, model, database path, and runtime flags used by the benchmark process. Provider/model selection is resolved once at startup and passed explicitly to planning and audit calls rather than re-read from the environment.

## Configure

| Variable               | Default                  | Purpose                                                                                                                   |
| ---------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `LLM_PROVIDER`         | `gemini`                 | Select `gemini` or `ollama`.                                                                                              |
| `GEMINI_API_KEY`       | unset                    | Authenticate Gemini. Require it when `LLM_PROVIDER=gemini` and for local provider/evaluator operations; HTTP RAG uses server credentials.               |
| `GEMINI_MODEL`         | `gemini-3.8-flash`       | Select the Gemini planning and safety-audit model.                                                                        |
| `OLLAMA_BASE_URL`      | `http://localhost:11434` | Select the Ollama API endpoint.                                                                                           |
| `OLLAMA_MODEL`         | `llama3`                 | Select the Ollama model.                                                                                                  |
| `APEX_API_KEY`         | unset                    | Require `X-Apex-Key` for all HTTP routes except `/health` when set. Require it before binding the server beyond loopback. |
| `APEX_DB_PATH`         | `~/.apex/memory.db`      | Store key-value memory and swarm bookkeeping.                                                                             |
| `APEX_HISTORY_DB_PATH` | `~/.apex/runs.db`        | Store run plans, metrics, and tool events.                                                                                |
| `APEX_MCP_SERVERS`     | `[]`                     | Load MCP servers from a JSON array of `{"name", "url", "headers"?}` objects.                                              |
| `RAG_BASE_URL`         | required for storage; legacy tool defaults to `http://localhost:8000` | Select the RAG service.                                                         |
| `RAG_API_TOKEN`        | unset                    | Authenticate the hosted RAG service.                                                                                      |
| `RAG_CHROMA_PATH`      | `~/.rag/chroma`          | Select the canonical mapped root; HTTP adapters never open it.                                                                                   |
| `RAG_COLLECTION`       | `documents-gemini-embedding-2` | Select the authorized HTTP namespace.                                                                                     |
| `RAG_CHUNK_SIZE`       | `512`                    | Set words per chunk.                                                                                                      |
| `RAG_CHUNK_OVERLAP`    | `64`                     | Set overlapping words between chunks.                                                                                     |
| `RAG_TOP_K`            | `5`                      | Set retrieved chunk count.                                                                                                |
| `RAG_SCORE_THRESHOLD`  | `0.4`                    | Filter retrieval results by cosine-similarity score.                                                                      |
| `RAG_EMBEDDING_MODEL`  | `gemini-embedding-2`     | Select the Gemini embedding model.                                                                                        |
| `RAG_GENERATION_MODEL` | `gemini-3.5-flash-lite`  | Select the grounded RAG generation model.                                                                                 |

Reject unsupported `LLM_PROVIDER` values during startup. Validate RAG chunk sizes, overlap, retrieval count, score threshold, and collection name before use.

## Architecture

Keep implementation modules under `apex/core/`. Preserve the top-level compatibility shims for established import paths.

```text
apex/
├── __main__.py         CLI and subcommand dispatch
├── config.py           runtime configuration
├── providers.py        Gemini/Ollama provider adapters
├── history.py          SQLite run/event history
├── export.py           history export
├── replay.py           recorded-plan replay
├── rsi.py              gated recursive-improvement experiment
├── bench.py            task benchmark harness
├── server.py           Flask HTTP API
├── mcp.py              MCP Streamable HTTP adapter
├── prompt.txt          plan-generation system prompt
└── core/
    ├── types.py        immutable plan/result/event/tool types
    ├── state.py        immutable runtime state
    ├── planner.py      prompt rendering and plan validation
    ├── loop.py         bounded execution loop
    ├── tools.py        built-in tools
    ├── toolloader.py   complete runtime registry construction
    ├── memory_store.py SQLite-backed memory tools
    ├── safety.py       plan audit
    ├── swarm.py        subprocess task dispatch
    ├── trace.py        JSONL trace writer
    └── rag/            HTTP RAG adapters and local provider exports
```

Import RAG modules through `apex.core.rag`; do not depend on a synthetic top-level `rag` package.

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

## HTTP API

Start a loopback server:

```bash
apex serve --host 127.0.0.1 --port 8080
```

Set an API key before binding beyond loopback:

```bash
export APEX_API_KEY='replace-with-a-secret'
apex serve --host 0.0.0.0 --port 8080
```

Refuse an unauthenticated non-loopback bind. Run the Flask process single-threaded because tool timeouts use `signal.alarm`, which requires main-thread execution.

| Route        | Method | Auth                         | Purpose                                                                           |
| ------------ | ------ | ---------------------------- | --------------------------------------------------------------------------------- |
| `/health`    | GET    | none                         | Return status and version.                                                        |
| `/run`       | POST   | `X-Apex-Key` when configured | Execute `{"task": "..."}` or an authorization-unbound exact `{"plan": {...}}`; return the run ID and validated plan. |
| `/authorized-run` | POST | same | Execute an exact plan only after atomically binding validated authorization metadata to its plan digest. |
| `/runs`      | GET    | same                         | Return recent runs with `?n=20`.                                                  |
| `/runs/<id>` | GET    | same                         | Return one run and its events.                                                    |
| `/replay`    | POST   | same                         | Replay with `simulate`, `dry`, or `live`.                                         |
| `/export`    | GET    | same                         | Export history as JSONL or CSV.                                                   |

## MCP

Configure MCP 2026-07-28 Streamable HTTP endpoints with `APEX_MCP_SERVERS`:

```bash
export APEX_MCP_SERVERS='[
  {"name":"local","url":"http://127.0.0.1:9000/mcp"}
]'
```

Add static request headers only when the server requires them:

```json
[
  {
    "name": "remote",
    "url": "https://example.invalid/mcp",
    "headers": {"Authorization": "Bearer token"}
  }
]
```

Send JSON-RPC `tools/list` and `tools/call` requests to each configured endpoint. Declare protocol version `2026-07-28` per request, include the required per-request MCP metadata, and emit `Mcp-Method`, `Mcp-Name`, and declared `Mcp-Param-*` routing headers where required.

Namespace loaded tools as `mcp__<server>__<tool>`. Skip malformed server definitions and unsupported tool schemas instead of inventing behavior. Reject MCP multi-round-trip input requests and Tasks-extension handles because APEX currently exposes only synchronous tool effects.

## RAG

`apex.core.rag.pipeline` and `apex.core.rag.store` use `rag.http_client.Client`
through the shared `rag.remote` adapters (requires matching RAG 1.5.0).
Set `RAG_BASE_URL=http://127.0.0.1:8000` explicitly for host-local storage calls.
There is no storage-client URL fallback. Only canonical `~/.rag/chroma`, namespace
`documents-gemini-embedding-2` and space `google-gemini / gemini-embedding-2 /
3072 / schema 1` are mapped. Other roots/namespaces/spaces fail before dispatch.
This host mapping does not configure Docker/infra connectivity.

File reads and ordered directory results stay local; text ingestion/query runs
on the server using its own `GEMINI_API_KEY`. Callers do not need or forward that
credential. Raw replacement/retrieval, delete and inspection use versioned HTTP.
Owner handles `_get_client` and `_get_collection` are no longer exposed; remote
create returns acknowledgement. Errors are explicit `RemoteError`, with no retry,
redirect, local fallback or client recovery. Unknown outcome never permits replay.

Preserve caller settings and APEX's `gemini-3.5-flash-lite` generation default;
RAG/CLI defaults to `gemini-2.5-flash`. Server policy permits both. Loopback needs
no bearer token; `RAG_API_TOKEN` may be sent when configured. Non-loopback server
authentication requirements remain intact.

`rag_multi_query` is unchanged: it uses legacy `POST /query`, its existing
`RAG_BASE_URL` default and server generation settings. Standalone embedder/generator
exports remain local. The evaluator intentionally imports local `rag.store` and
retains `documents`, local embedding and existing retrieval settings. It cannot
open the same root concurrently with its server owner; no evaluator migration or
namespace grant is implied.

Re-embed every existing collection after changing `RAG_EMBEDDING_MODEL`. Do not mix vectors produced by `gemini-embedding-2` with vectors from `gemini-embedding-001`, `text-embedding-004`, or any other embedding space.

Re-ingest a document to replace all of its previous chunks. Use directory-relative document IDs during recursive directory ingestion so files with identical basenames in different directories remain distinct. Preserve deterministic result ordering even when embedding files concurrently.

Evaluate retrieval quality with:

```bash
python benchmarks/eval_rag.py --dataset benchmarks/eval_rag_dataset.json
```


### Exact plan submission

`POST /run` accepts exactly one of `{"task": "..."}` or `{"plan": {...}}`.
Task requests use the planner as before. Plan requests use the same registry/schema
validation and existing execution kernel, without an LLM planning call. Invalid
plans return 400 before any tool runs. A plan requires a non-empty `goal`, typed
`steps`, and a final halt; the 32-step ceiling includes that halt. Authentication
and response fields are identical for both request forms. ASON 0.2+ uses this
interface to preserve its pre-execution policy decisions.

The `apex.core.rag` imports delegate to the canonical `axiom-rag>=1.5.0`
implementation. APEX retains its existing model defaults through its config
adapter. Retrieval changes and regressions belong in `axiom-rag`; both packages
use the same chunking, embedding, storage, and ingestion functions.

## RSI experiment

Run RSI from a clean source checkout with development dependencies installed (`pip install -e ".[dev]"`); its regression gate requires pytest. Use a working tree you can discard or review. Let each cycle benchmark a baseline, ask the configured LLM provider for candidate unified diffs, use Git’s patch parser to reject candidates outside the allowed files, binary changes, file creation/deletion, renames/copies, mode changes, or blocked shell patterns, require each candidate to pass offline regression tests before benchmarking in a scratch worktree, and commit the selected candidate to `rsi/cycle-N`.

Candidate tests and each benchmark invocation have a 300-second timeout. Failed tests, failed benchmark processes, and invalid/non-finite scores are ineligible for selection. Candidate regressions and benchmarks share a Linux Bubblewrap boundary; install Bubblewrap 0.9+ with `--size` support (for example, `sudo apt-get install bubblewrap` on Ubuntu 24.04) and enable unprivileged user namespaces. Isolation setup failures abort RSI with a diagnostic; there is no unrestricted fallback.

The sandbox exposes the disposable worktree read-only at `/source` and copies it into private, size-limited tmpfs at `/work`, with read-only system executable/library directories and the active Python runtime's `bin`, `lib`, and venv configuration. Install dependencies as packages in that runtime: editable dependencies pointing to other checkouts are deliberately inaccessible. The real repository, host home contents, credentials, and privileged sockets are not mounted. `/tmp` and `HOME` are private temporary filesystems; the sandbox root and `/proc` are read-only. A positive environment allowlist supplies deterministic runtime settings, and inherited descriptors and standard input are closed.

Separate network and PID namespaces block host loopback/external connections and contain descendants, including detached children. Bubblewrap's PID-1 reaper and parent-death handling tear down descendants on exit; the executor also kills the process group on timeout or Python interruption. Candidate benchmarks are offline: provider credentials and network access are never forwarded. Network-enabled evaluation would need a separately designed capability.

The host suite and APEX CI run real isolation probes, including a full valid-candidate regression/benchmark smoke test. Tests marked `host_isolation` require a host outside the boundary and are excluded only from recursive candidate regression runs; all other offline regressions remain mandatory. This boundary relies on the Linux kernel, systemd user manager, and trusted installed runtime/Bubblewrap.

Each regression or benchmark invocation starts in its own unprivileged systemd scope on cgroup v2. The trusted launcher verifies the actual kernel limits before executing Bubblewrap; missing user-manager access, controller delegation, or limits fail closed. Operators must provide a running user manager with `cpu`, `memory`, and `pids` delegated, and the cgroup-v2 mount must enable `nsdelegate` so nested namespaces cannot rewrite their resource limits. On a dedicated CI host, configure a `user@UID.service` drop-in with `[Service]` and `Delegate=cpu memory pids`, reload systemd, and start/restart that user manager. The workflow uses a temporary `/run/systemd/system` drop-in and Ubuntu 24.04 for the required Bubblewrap version. It also loads a bwrap-specific AppArmor user-namespace allowance so the trusted sandbox builder can configure its namespaces. Candidate code never receives the manager's socket or credentials.

| Resource | Default per invocation |
| --- | --- |
| Aggregate CPU rate | 100% of one CPU, shared by all workers |
| Wall time | 300 seconds, including setup and output draining |
| Cgroup memory | 1 GiB including descendants and charged kernel/tmpfs memory |
| Swap | Disabled for the candidate cgroup |
| Processes and threads | 256 total tasks, including sandbox helpers |
| Writable candidate files | 256 MiB private `/work` tmpfs |
| Temporary files | 64 MiB private `/tmp` tmpfs |
| Home / shared memory | 16 MiB each at `HOME` and `/dev/shm` |
| Captured stdout + stderr | 1 MiB combined, then termination and rejection |
| Open descriptors / core dumps | 1,024 per process / disabled |

A group OOM kills the whole evaluation. Timeouts, output excess, exceptions, and controller death retain descendant cleanup. Nonzero resource failures and output-limit exceptions cannot produce eligible scores. Source worktrees remain unchanged during execution and are removed by RSI afterward; writable changes in tmpfs are discarded after each invocation. Benchmarks therefore begin from the same patched source, rather than retaining regression or prior-benchmark writes.

CPU quota bounds aggregate rate, not exclusive CPU access; the wall timeout bounds duration, with normal scheduler/period granularity. There is no separate numeric inode quota: tmpfs metadata is charged to the cgroup memory limit and covered by a small-file exhaustion probe. The trusted Git snapshot and installed read-only runtime remain host-managed storage. Additional private mounts, if created in nested namespaces, remain subject to the aggregate 1 GiB cgroup memory ceiling; the table lists the initial tmpfs capacities. Limits apply per invocation, not across independent RSI controllers. No network-enabled or unrestricted resource bypass is provided.

Do not auto-merge RSI branches. Review every candidate manually. Keep `apex/core/safety.py` outside the patchable set.

## Test

Run syntax validation:

```bash
python -m compileall -q apex benchmarks tests
```

Run offline unit tests without a Gemini API key:

```bash
python -m pytest tests/ -m 'not integration' -q
```

Run integration tests with the selected live provider configured:

```bash
python -m pytest tests/ -q
```

Run mock benchmarks without external model access:

```bash
python -m apex.bench --mock
python benchmarks/parallel_codegen.py --mock
```

## Container

Set both service credentials before exposing the execution API:

```bash
export GEMINI_API_KEY='...'
export APEX_API_KEY='replace-with-a-secret'
docker compose up --build
```

Set `LLM_PROVIDER=ollama` instead of `GEMINI_API_KEY` when the container can reach the configured Ollama endpoint. Require `APEX_API_KEY` for the Compose deployment because it binds port 8080 beyond loopback.

Persist APEX memory and history state in the `apex_data` volume. Deploy the trusted policy application separately and point it at the APEX HTTP API; prevent callers from bypassing that application.

## Ecosystem

* Use `axiom-ason` for caller-supplied pre-execution policy through a trusted application; do not infer automatic rollback.
* Use `axiom-demos` for applied integration examples.
* Use `axiom-research` for formal writeups.
* Use `axiom-llc.github.io` for the project site.

© AXIOM LLC.

Custom tools default to one execution attempt. Set `retry_safe=True` only when repeating the effect after a timeout or partial failure is safe. Shell, filesystem writes, memory writes, and MCP tools are not retried by default.

### Provider boundary checks

Make one generation attempt per provider call. Gemini uses a 60-second HTTP
timeout; Ollama uses 300 seconds. Return a generic provider failure without
recording upstream exception bodies, credentials, or prompt text. Retry explicitly
only after considering possible completed generation and quota usage.

Manual checks on 2026-09-11 exercised Gemini generation and invalid-model failure,
plus canonical RAG generation with `gemini-3.5-flash-lite`. The local Ollama server
accepted an explicit `OLLAMA_MODEL=gemma3:1b`; its uninstalled default `llama3`
failed cleanly. Set `OLLAMA_MODEL` to an installed model before selecting Ollama.
Run the existing integration tests explicitly with configured credentials; keep
hosted CI offline.
