[![PyPI](https://img.shields.io/pypi/v/axiom-apex.svg)](https://pypi.org/project/axiom-apex/)
# axiom-apex

**v2.2.0** · Deterministic agentic runtime for AI-driven task execution — schema-validated plans, bounded tool execution, benchmark-driven self-optimization, and full audit trails without the non-determinism of conventional agent frameworks. Python 3.11+ · Gemini 2.5 Flash · MIT

![CI](https://github.com/axiom-llc/axiom-apex/actions/workflows/ci.yml/badge.svg)

```bash
export GEMINI_API_KEY=your-key
apex "analyse this codebase and produce a refactoring plan"
```

---

# Operational Paradigm & Execution Mechanics

APEX translates natural language tasks into validated JSON execution plans and runs them as a deterministic sequence of isolated tool invocations. Identical input always produces identical tool calls. Every step is logged to an immutable history. No hidden state, no runtime configuration, no framework magic.

---

## Installation

From source (requires Python 3.11+):
```bash
git clone https://github.com/axiom-llc/axiom.git ~/c/apps/axiom
cd ~/c/apps/axiom
python3.12 -m venv .venv && source .venv/bin/activate
pip install -e .
```

---

## Usage

```bash
apex "write system info and today's date to ~/report.txt"
apex "fetch https://wttr.in/London using curl and save to ~/weather.txt"
apex "analyse ~/logs/app.log for ERROR lines and count them"
apex "save current git branch to memory as active_branch"
apex "read from memory the key active_branch"
```

### Flags

**`--interactive`**, **`-i`** — Interactive prompt mode. `exit` or Ctrl-D to quit.

**`--dry-run`** — Print execution plan as JSON. No tools invoked.

**`--trace`** — Stream each step result to stderr.

**`--full-trace`** — Write structured JSONL trace events to file or stderr.

**`--trace-path <path>`** — JSONL trace output file. Used with `--full-trace`.

**`--paranoid`** — Audit plan for dangerous operations before any tool is invoked. Blocks on unsafe plans.

**`--version`** — Print version and exit.

---

## Swarm Mode

```bash
apex swarm --tasks tasks.json --workers 4
apex swarm --tasks tasks.json --workers 4 --human-loop
apex swarm --tasks tasks.json --workers 4 --trace-path ~/traces/swarm.jsonl
```

`tasks.json` — array of task prompt strings. `--human-loop` pauses for confirmation before each batch. Recommended workers ceiling: 4 for Gemini 2.5 Flash.

---

## Run History

Every run is persisted to SQLite at `~/.apex/runs.db`. Every tool invocation within a run is recorded as a step event.

```bash
apex history        # list last 20 runs
apex history -n 50  # list last N runs
apex stats          # aggregate metrics as JSON
```

`apex stats` output:
```json
{
  "total": 42,
  "passed": 39,
  "pass_rate": 0.9286,
  "avg_tokens": 1823.4,
  "avg_wall_seconds": 12.341
}
```

Schema:
```
runs(id, task, plan_json, exit_code, token_count, wall_seconds, timestamp)
events(id, run_id, step, tool, args_json, result_json, timestamp)
```

---

## Replay

Re-execute any recorded run without re-querying the LLM.

```bash
apex replay 42                        # simulate using recorded step outputs
apex replay 42 --mode dry             # print plan JSON only
apex replay 42 --mode live            # re-execute against current registry
apex replay 42 --mode simulate --diff # compare simulated vs recorded outputs
apex replay 42 --mode live --no-write # live replay with write_file disabled
```

Replay modes:
- `simulate` — stubs all tools using recorded outputs from `events` table. No side effects.
- `dry` — prints the recorded plan JSON. No execution.
- `live` — full re-execution against the current tool registry. Real side effects.

---

## Export

Dump run history to flat files for external analysis.

```bash
apex export                                    # JSONL to stdout
apex export --format csv                       # CSV to stdout
apex export --format jsonl --since 2026-01-01  # filter by date
apex export --fields id,task,exit_code         # select fields
apex export --events                           # include step-level events
apex export --format csv -o ~/runs.csv         # write to file
```

---

## HTTP API

`apex serve` exposes a Flask HTTP API for programmatic plan submission and run inspection.

```bash
apex serve                          # bind 127.0.0.1:8080
apex serve --host 0.0.0.0           # expose on all interfaces
apex serve --host 0.0.0.0 --port 9090
```

Set `APEX_API_KEY` to require authentication on all endpoints:

```bash
export APEX_API_KEY=your-secret-key
apex serve
```

Requests must include `X-Apex-Key: your-secret-key`. If `APEX_API_KEY` is unset, the server starts without auth (warning printed at startup).

### Endpoints

**`GET /health`**
```json
{"status": "ok", "version": "2.2.0"}
```

**`POST /run`** — Submit a task for execution.
```bash
curl -X POST http://127.0.0.1:8080/run \
  -H "Content-Type: application/json" \
  -H "X-Apex-Key: your-secret-key" \
  -d '{"task": "write hello world to /tmp/hello.txt"}'
```
Response: `{run_id, plan, exit_code, status, output, token_count, step_count}`

**`GET /runs`** — List last 20 run summaries.

**`GET /runs/<id>`** — Full run dict + events list for a specific run.

**`POST /replay`** — Replay a recorded run.
```json
{"run_id": 42, "mode": "simulate"}
```
Response: `{run_id, mode, exit_code, output}`

**`GET /export`** — Stream run history. Accepts `?format=csv|jsonl&since=YYYY-MM-DD`.

---

## Benchmark Harness & Fitness Score

```bash
python -m apex.bench --tasks apex/benchmarks/tasks.json --mock
python -m apex.bench --tasks apex/benchmarks/tasks.json
python -m apex.bench --tasks apex/benchmarks/tasks.json --out apex/benchmarks/results/run.json
```

`--mock` skips real apex calls — safe for CI without `GEMINI_API_KEY`.

Each run produces a normalized `apex_score`:

```
apex_score = pass_rate × speed_factor × token_efficiency
```

- `pass_rate` — fraction of tasks that passed
- `speed_factor` — 1.0 at ≤10s/task, degrades linearly; floor 0.01
- `token_efficiency` — derived from `~/.apex/runs.db`; 1.0 at ≤1000 tokens/run

---

## Benchmark-Driven Self-Optimization (BDSO)

`apex/bench.py` coordinates continuous Benchmark-Driven Self-Optimization (BDSO) optimization cycles. Main is never touched without human approval.

```bash
python -m apex.bench --rsi --cycles 3 --budget-tokens 50000
python -m apex.bench --rsi --cycles 1 --mock-bench
```

**Cycle sequence:**
1. Run bench → compute `apex_score`
2. Read BDSO-eligible source files
3. Generate N=3 candidate patches via LLM
4. Structural validation on each candidate (banned patterns, file allowlist)
5. Score each candidate in isolation (k=3 bench runs, mean score)
6. Apply highest-scoring candidate on `rsi/cycle-N` branch via `patch -p1 --fuzz=3`
7. Print delta + human review gate before any merge

**Governor hard caps:** max cycles · max token budget · max wall time (1h). All enforced before each cycle.

**BDSO-eligible files:** `apex/core/loop.py` · `apex/core/planner.py` · `apex/llm.py`

---

## Safety & Policy Verification

`--paranoid` runs a two-stage pre-execution safety audit managed in-process:

1. **Static prefilter (`core/validator.py`)** — deterministic regex rules block known-dangerous patterns (`rm -rf /`, `curl | sh`, writes outside `$HOME`, etc.) before any LLM call.
2. **LLM audit (`core/validator.py`)** — Gemini audits the full plan for destructive, exfiltration, or privilege-escalation patterns. Returns structured risk assessment.

Execution is blocked if either stage rejects the plan. 

`validator.py` is a permanent safety boundary and is never BDSO-eligible.

---

## Tools

**`shell`** `cmd: str` — Execute shell command. Returns stdout, stderr, exit code.

**`read_file`** `path: str` — Read file contents.

**`write_file`** `path: str, content: str` — Write to file. Creates parent dirs as needed.

**`http_get`** `url: str, headers?: dict` — HTTP GET. Returns body and status code.

**`rag_multi_query`** `queries: list[str], top_k?: int` — Multi-hop semantic retrieval handled in-process via embedded RAG modules (`core/rag.py`).

**`memory_read`** `key?: str` — Read from persistent memory. Omit `key` to list all entries.

**`memory_write`** `key: str, value: any` — Write JSON-serialisable value to persistent memory.

Memory is backed by SQLite at `~/.apex/memory.db`.

---

## Configuration

**`GEMINI_API_KEY`** *(required)* — Gemini API key.

**`APEX_API_KEY`** *(optional)* — API key for `apex serve` authentication. If unset, server starts without auth.

**`APEX_DB_PATH`** *(optional, default: `~/.apex/memory.db`)* — SQLite memory database path.

**`LLM_PROVIDER`** *(optional, default: `gemini`)* — Set to `ollama` to use local Ollama. `GEMINI_API_KEY` not required when using Ollama.

**`OLLAMA_BASE_URL`** *(optional, default: `http://localhost:11434`)* — Ollama base URL.

**`OLLAMA_MODEL`** *(optional, default: `llama3`)* — Ollama model name.

**`APEX_MCP_SERVERS`** *(optional)* — JSON array of MCP server configs. Tools injected into registry at startup.

---

## Architecture

```
apex/
  __main__.py     <- CLI entry; builds registry, dispatches subcommands, calls run()
  config.py       <- Frozen Config dataclass, resolved once at startup
  providers.py    <- Provider abstraction: GeminiProvider, OllamaProvider, get_provider()
  llm.py          <- Thin shim delegating to providers.py
  server.py       <- Flask HTTP API hosting execution & in-process RAG endpoints
  history.py      <- record_run(), record_event(), list_runs(), aggregate_stats()
  templates.json  <- Consolidated policy profiles (law-firm, healthcare-rcm, etc.)
  prompt.txt      <- System + planner prompt
  mcp.py          <- MCP client adapter
  core/
    types.py      <- Frozen dataclasses: Plan, Step, Result, Tool, Event
    state.py      <- Immutable State; memory_read and memory_write persistence
    planner.py    <- Prompt rendering, JSON plan parsing, Pydantic schema validation
    loop.py       <- Pure run(task, config, registry) -> State; writes runs + events
    trace.py      <- JSONL trace write, run export, and simulation replays
    swarm.py      <- Parallel swarm coordinator with human-in-loop
    validator.py  <- Static prefilter + LLM plan auditor (merges validation & paranoid)
    rollback.py   <- Structural state rollback on task execution failure
    schema.py     <- Schema definitions for execution safety policies
    tools.py      <- Native tool definitions: shell, read_file, write_file, http_get
    rag.py        <- Embedded semantic search pipeline (chunker, embedder, vector-store, query)
  benchmarks/
    tasks.json    <- Default benchmark task definitions
    eval_rag.py   <- RAG accuracy and retrieval metric scoring engine
    results/      <- Local and CI benchmark run output JSONs
  examples/
    cli_demos.sh  <- Compiled CLI orchestration templates & swarms
    logistics-dashboard/ <- Logistics dashboard (SQLite + compliance reports)
    voice-agent/  <- Voice automation agent container (Gemini + Twilio + Flask)
  tests/
    test_apex.py   <- Core execution regression test suite
    test_policy.py <- Safety policy and contract verification tests
    test_rag.py    <- Chunking and embedding store tests
    test_ivr.py    <- IVR webhook mock tests
    testdata/      <- Local mock policy data and corpus texts
docs/
  research/       <- Theoretical and systems papers (deterministic safety, taxonomies)
  web/            <- Public taxonomy page and static web landing resources
```

### Design Axioms

**Immutability.** All core types are frozen dataclasses. `State` updated via `dataclasses.replace()` — never mutated in place.

**Pure execution loop.** `run()` is a pure function: same plan + config produces same tool call sequence.

**Schema-validated plans.** Every LLM plan validated against tool registry via Pydantic before invocation.

**Bash is the concurrency primitive.** No threads. No async. Parallelism via processes.

**Zero implicit configuration.** `Config` resolved once at startup, passed explicitly to every function.

**BDSO never touches main.** All cycles operate on isolated `rsi/cycle-N` branches. Human merge required.

**Deterministic safety.** Static prefilter runs before any LLM audit — dangerous patterns blocked without a network call.

### Data Flow

```
argv
 -> main()
      |- load_config()            -> Config
      |- make_memory_tools()      -> Tool, Tool
      |- {shell, read_file, ...}  -> registry: dict[str, Tool]
      -> run(task, config, registry)
           |- generate_plan()     -> State (schema-validated)
           |- static_audit()      -> safe | block  (deterministic)
           |- paranoid LLM audit  -> safe | block  (if --paranoid)
           -> loop over steps
                |- ToolCall -> tool.effect(args) -> Ok | Err -> State
                           -> record_event()     -> ~/.apex/runs.db (events)
                -> Halt    -> State(status=HALTED)
           -> record_run()        -> ~/.apex/runs.db (runs)
```

### Exit Codes

`0` — HALTED. `1` — ERROR. `2` — unexpected terminal state.

---

## Tests

```bash
pytest apex/tests/ -q
```

CI runs on Python 3.11 and 3.12 on every push.

---

## Scripting & Parallelism

### Parallel Tasks

```bash
apex "write planet report for Mars to ~/mars.txt" &
apex "write planet report for Jupiter to ~/jupiter.txt" &
wait
```

### Iterative Fix Loop

```bash
for i in $(seq 1 "$ITERATIONS"); do
    python3 "$OUTPUT" 2>"$LOG" && break
    apex "read ${OUTPUT}, read ${LOG}, fix all errors and write back to ${OUTPUT}"
done
```

---

## Examples & Industry Profiles

The centralized blueprints directory provides complete run loops for live customer operations:

1. **Logistics Dashboard (`examples/logistics-dashboard`)** — compliance audits, automated shipments ledger ingestion, and real-time visualization dashboards.
2. **Twilio Voice Agent (`examples/voice-agent`)** — GCP Cloud Run container deploying Gemini pipelines with Twilio webhook routing.

Centralized configuration templates inside `templates.json` ship with restrictive safety profiles. Four representative profiles:

**Law firm** — document-centric, no egress required
```json
{
  "max_steps": 12,
  "allowed_tools": ["read_file", "write_file"],
  "blast_radius": "local"
}
```

**Healthcare RCM** — compliance-sensitive, filesystem-only
```json
{
  "max_steps": 8,
  "allowed_tools": ["read_file", "write_file"],
  "blast_radius": "local",
  "rollback_on_failure": true
}
```

**Hedge fund** — requires live market data ingestion via HTTP
```json
{
  "max_steps": 16,
  "allowed_tools": ["http_get", "write_file"],
  "blast_radius": "network"
}
```

**MSP / DevOps** — local ops with shell access, no network writes
```json
{
  "max_steps": 10,
  "allowed_tools": ["shell", "read_file", "write_file", "delete_file"],
  "blast_radius": "local"
}
```

`blast_radius=local` blocks all HTTP tools at the API boundary before execution. `blast_radius=none` additionally blocks write and delete operations — enforced structurally, not by prompt.

---

## Extending APEX

**1. `apex/core/tools.py`:**
```python
LIST_DIR = Tool(
    name="list_dir",
    input_spec={"path": str},
    output_spec={"items": list, "count": int},
    effect=lambda args: {"items": [str(i) for i in Path(args["path"]).iterdir()], "count": len(list(Path(args["path"]).iterdir()))},
)
```

**2. `apex/__main__.py`:** add `"list_dir": LIST_DIR` to `registry`.

**3. `apex/prompt.txt`:** add `- list_dir: list directory contents. args: {path}. returns: {items, count}`

---

## Constraints

- Max plan steps: 32
- Tool timeout: 300s
- Max tool output: 10 MB
- Concurrency ceiling: 4 concurrent processes (Gemini 2.5 Flash)
- Platform: Unix (SIGALRM-based timeout)

---

## License

MIT — [AXIOM LLC](https://axiom-llc.github.io)
