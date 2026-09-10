# axiom-apex

Run bounded AI-agent tasks by compiling natural language into schema-validated plans, executing explicit tool calls, and recording complete plans and tool events for inspection and replay.

## Install

Create an isolated environment and install development dependencies:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
```

Use Python 3.11+. Set `GEMINI_API_KEY` for the default Gemini provider, or set `LLM_PROVIDER=ollama` and run a local Ollama server.

## Run

```bash
apex "write 'hello world' to /tmp/out.txt and read it back"
apex --dry-run "write hello to /tmp/out.txt"
apex --paranoid "..."
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

Compute `apex_score = pass_rate × speed_factor × token_efficiency`. Keep each factor in the inclusive range `0.01..1.0`, except `pass_rate`, which may be `0.0`.

## Configure

| Variable               | Default                  | Purpose                                                                                                                   |
| ---------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `LLM_PROVIDER`         | `gemini`                 | Select `gemini` or `ollama`.                                                                                              |
| `GEMINI_API_KEY`       | unset                    | Authenticate Gemini. Require it when `LLM_PROVIDER=gemini` and for Gemini-backed in-process RAG operations.               |
| `GEMINI_MODEL`         | `gemini-3.8-flash`       | Select the Gemini planning and safety-audit model.                                                                        |
| `OLLAMA_BASE_URL`      | `http://localhost:11434` | Select the Ollama API endpoint.                                                                                           |
| `OLLAMA_MODEL`         | `llama3`                 | Select the Ollama model.                                                                                                  |
| `APEX_API_KEY`         | unset                    | Require `X-Apex-Key` for all HTTP routes except `/health` when set. Require it before binding the server beyond loopback. |
| `APEX_DB_PATH`         | `~/.apex/memory.db`      | Store key-value memory and swarm bookkeeping.                                                                             |
| `APEX_HISTORY_DB_PATH` | `~/.apex/runs.db`        | Store run plans, metrics, and tool events.                                                                                |
| `APEX_MCP_SERVERS`     | `[]`                     | Load MCP servers from a JSON array of `{"name", "url", "headers"?}` objects.                                              |
| `RAG_BASE_URL`         | `http://localhost:8000`  | Select the separate hosted RAG service used by `rag_multi_query`.                                                         |
| `RAG_API_TOKEN`        | unset                    | Authenticate the hosted RAG service.                                                                                      |
| `RAG_CHROMA_PATH`      | `~/.rag/chroma`          | Store the in-process RAG ChromaDB data.                                                                                   |
| `RAG_COLLECTION`       | `documents`              | Select the in-process RAG collection.                                                                                     |
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
    ├── safety.py       paranoid plan audit
    ├── swarm.py        subprocess task dispatch
    ├── trace.py        JSONL trace writer
    └── rag/            in-process RAG pipeline
```

Import in-process RAG modules through `apex.core.rag`; do not depend on a synthetic top-level `rag` package.

## Planning and execution

Limit generated plans to 32 total steps. Require a non-empty goal, validate every tool name and argument against the active registry, reject unknown or missing arguments and incompatible argument types, and require exactly one final halt step.

Build planner tool documentation from the active registry so built-in, memory, user-defined, and MCP tools use the same runtime schema.

Enforce a 300-second timeout per tool call, retry failures up to three times only for tools explicitly marked `retry_safe=True` (built-in file/memory reads and HTTP GET), reject non-JSON-serializable tool output, and reject serialized tool output above 10 MiB.

Record the complete validated plan before execution mutates runtime state. Persist each run and its tool events atomically in `APEX_HISTORY_DB_PATH` with SQLite WAL enabled.

## Safety

Use `--paranoid` to run deterministic checks and an LLM plan audit before execution. Treat this audit as an advisory pre-execution safeguard, not a complete policy boundary.

Allow `write_file` targets only under the current home directory or `/tmp` in paranoid mode. Match resolved path boundaries rather than string prefixes.

Run untrusted workloads behind an external policy/rollback layer such as `axiom-ason`; `axiom-apex` does not provide transactional rollback.

## Replay

Use recorded plans directly; do not ask the planner to regenerate a live replay.

```bash
apex replay 42 --mode simulate
apex replay 42 --mode dry
apex replay 42 --mode live --diff
apex replay 42 --mode live --no-write
```

Use `simulate` to print recorded tool events without executing anything. Use `dry` to print the recorded plan. Use `live` to validate the recorded plan against the current registry and execute that exact plan. Use `--diff` to compare live tool results with recorded results. Use `--no-write` to reject plans requiring `write_file`.

Treat live replay as deterministic plan replay, not deterministic external effects: files, networks, subprocesses, remote services, and time-dependent state may produce different results.

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
| `/run`       | POST   | `X-Apex-Key` when configured | Execute `{"task": "..."}` or an exact `{"plan": {...}}`; return the run ID and validated plan. |
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

Use `apex.core.rag.pipeline` for the in-process pipeline:

1. Chunk documents by fixed word windows or sentence groups.
2. Format `gemini-embedding-2` text for asymmetric search retrieval.
3. Embed each document chunk independently and embed queries separately.
4. Store vectors in ChromaDB with cosine distance.
5. Retrieve matching chunks and generate an answer constrained to retrieved context.

Use `rag_multi_query` only for the separate HTTP RAG service configured by `RAG_BASE_URL`.

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

The `apex.core.rag` imports delegate to the canonical `axiom-rag>=1.1.0`
implementation. APEX retains its existing model defaults through its config
adapter. Retrieval changes and regressions belong in `axiom-rag`; both packages
use the same chunking, embedding, storage, and ingestion functions.

## RSI experiment

Run RSI from a clean source checkout with development dependencies installed (`pip install -e ".[dev]"`); its regression gate requires pytest. Use a working tree you can discard or review. Let each cycle benchmark a baseline, ask the configured LLM provider for candidate unified diffs, use Git’s patch parser to reject candidates outside the allowed files, binary changes, file creation/deletion, renames/copies, mode changes, or blocked shell patterns, require each candidate to pass offline regression tests before benchmarking in a scratch worktree, and commit the selected candidate to `rsi/cycle-N`.

Candidate tests and each benchmark invocation have a 300-second timeout. Failed tests, failed benchmark processes, and invalid/non-finite scores are ineligible for selection. Candidate regressions and benchmarks share a Linux Bubblewrap boundary; install `bubblewrap` (for example, `sudo apt-get install bubblewrap`) and enable unprivileged user namespaces. Isolation setup failures abort RSI with a diagnostic; there is no unrestricted fallback.

The sandbox exposes the disposable worktree read-only at `/source` and copies it into private, size-limited tmpfs at `/work`, with read-only system executable/library directories and the active Python runtime's `bin`, `lib`, and venv configuration. Install dependencies as packages in that runtime: editable dependencies pointing to other checkouts are deliberately inaccessible. The real repository, host home contents, credentials, and privileged sockets are not mounted. `/tmp` and `HOME` are private temporary filesystems; the sandbox root and `/proc` are read-only. A positive environment allowlist supplies deterministic runtime settings, and inherited descriptors and standard input are closed.

Separate network and PID namespaces block host loopback/external connections and contain descendants, including detached children. Bubblewrap's PID-1 reaper and parent-death handling tear down descendants on exit; the executor also kills the process group on timeout or Python interruption. Candidate benchmarks are offline: provider credentials and network access are never forwarded. Network-enabled evaluation would need a separately designed capability.

The host suite and APEX CI run real isolation probes, including a full valid-candidate regression/benchmark smoke test. Tests marked `host_isolation` require a host outside the boundary and are excluded only from recursive candidate regression runs; all other offline regressions remain mandatory. This boundary relies on the Linux kernel, systemd user manager, and trusted installed runtime/Bubblewrap.

Each regression or benchmark invocation starts in its own unprivileged systemd scope on cgroup v2. The trusted launcher verifies the actual kernel limits before executing Bubblewrap; missing user-manager access, controller delegation, or limits fail closed. Operators must provide a running user manager with `cpu`, `memory`, and `pids` delegated, and the cgroup-v2 mount must enable `nsdelegate` so nested namespaces cannot rewrite their resource limits. On a dedicated CI host, provision it with `sudo systemctl start user@"$(id -u)".service` and `sudo systemctl set-property user@"$(id -u)".service 'Delegate=cpu memory pids'`. Candidate code never receives the manager's socket or credentials.

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

Persist APEX memory and history state in the `apex_data` volume. Deploy any external policy/rollback service separately and point it at the APEX HTTP API.

## Ecosystem

* Use `axiom-ason` to enforce pre-execution policy and rollback outside APEX.
* Use `axiom-demos` for applied integration examples.
* Use `axiom-research` for formal writeups.
* Use `axiom-llc.github.io` for the project site.

© AXIOM LLC.

Custom tools default to one execution attempt. Set `retry_safe=True` only when repeating the effect after a timeout or partial failure is safe. Shell, filesystem writes, memory writes, and MCP tools are not retried by default.
