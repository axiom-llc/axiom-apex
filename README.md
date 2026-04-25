[![PyPI](https://img.shields.io/pypi/v/axiom-apex.svg)](https://pypi.org/project/axiom-apex/)
# APEX — Agentic Process Executor

**v2.1.0** · Pure-functional CLI framework for deterministic, reproducible AI-driven workflows. Python 3.11+ · Gemini 2.5 Flash · MIT

![CI](https://github.com/axiom-llc/axiom-apex/actions/workflows/ci.yml/badge.svg)

```bash
export GEMINI_API_KEY=your-key
apex "analyse this codebase and produce a refactoring plan"
```

---

## What It Does

APEX translates natural language tasks into validated JSON execution plans and runs them as a deterministic sequence of isolated tool invocations. Identical input always produces identical tool calls. Every step is logged to an immutable history. No hidden state, no runtime configuration, no framework magic.

---

## Installation

```bash
pip install axiom-apex
```

Or from source (requires Python 3.11+):
```bash
git clone https://github.com/axiom-llc/axiom-apex.git ~/c/apps/axiom-apex
cd ~/c/apps/axiom-apex
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

Every run is persisted to SQLite at `~/.apex/runs.db`.

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

Schema: `runs(id, task, plan_json, exit_code, token_count, wall_seconds, timestamp)`

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

## Recursive Self-Improvement

`apex rsi` runs automated improvement cycles against the benchmark. Main is never touched without human approval.

```bash
apex rsi --cycles 3 --budget-tokens 50000
apex rsi --cycles 1 --mock-bench
```

**Cycle sequence:**
1. Run bench → compute `apex_score`
2. Read RSI-eligible source files
3. Generate unified diff via LLM
4. Structural validation (banned patterns, file allowlist)
5. Apply on `rsi/cycle-N` branch via `patch -p1 --fuzz=3`
6. Re-run bench → compare scores
7. Print delta + human review gate before any merge

**Governor hard caps:** max cycles · max token budget · max wall time (1h). All enforced before each cycle.

**RSI-eligible files:** `apex/core/loop.py` · `apex/core/planner.py` · `apex/llm.py` · `apex/paranoid.py`

---

## Tools

**`shell`** `cmd: str` — Execute shell command. Returns stdout, stderr, exit code.

**`read_file`** `path: str` — Read file contents.

**`write_file`** `path: str, content: str` — Write to file. Creates parent dirs as needed.

**`http_get`** `url: str, headers?: dict` — HTTP GET. Returns body and status code.

**`rag_multi_query`** `queries: list[str], top_k?: int` — Multi-hop semantic retrieval via axiom-rag.

**`memory_read`** `key?: str` — Read from persistent memory. Omit `key` to list all entries.

**`memory_write`** `key: str, value: any` — Write JSON-serialisable value to persistent memory.

Memory is backed by SQLite at `~/.apex/memory.db`.

---

## Configuration

**`GEMINI_API_KEY`** *(required)* — Gemini API key.

**`APEX_DB_PATH`** *(optional, default: `~/.apex/memory.db`)* — SQLite memory database path.

**`LLM_PROVIDER`** *(optional, default: `gemini`)* — Set to `ollama` to use local Ollama. `GEMINI_API_KEY` not required when using Ollama.

**`APEX_MCP_SERVERS`** *(optional)* — JSON array of MCP server configs. Tools injected into registry at startup.

---

## Architecture

```
apex/
  __main__.py     <- CLI entry; builds registry, calls run()
  config.py       <- Frozen Config dataclass, resolved once at startup
  llm.py          <- Gemini + Ollama adapters (stateless)
  memory.py       <- make_memory_tools(db_path) -> (memory_read, memory_write)
  history.py      <- record_run(), list_runs(), aggregate_stats() -> ~/.apex/runs.db
  tools.py        <- shell, read_file, write_file, http_get, rag_multi_query
  bench.py        <- Benchmark harness + apex_score fitness function
  rsi.py          <- RSI loop + CycleGovernor
  paranoid.py     <- Plan auditor — safety gate before execution
  mcp.py          <- MCP client adapter
  toolloader.py   <- Tool autoloading from ~/.apex/tools/
  prompt.txt      <- System + planner prompt
  benchmarks/
    tasks.json    <- Default benchmark task definitions
    results/      <- CI and local benchmark output JSONs
  core/
    types.py      <- Frozen dataclasses: Plan, Step, Result, Tool, Event
    state.py      <- Immutable State; format_output
    planner.py    <- Prompt rendering, JSON plan parsing, Pydantic schema validation
    loop.py       <- Pure run(task, config, registry) -> State; writes to runs.db
    trace.py      <- JSONL write_event
    swarm.py      <- Parallel swarm coordinator with human-in-loop
```

### Design Axioms

**Immutability.** All core types are frozen dataclasses. `State` updated via `dataclasses.replace()` — never mutated in place.

**Pure execution loop.** `run()` is a pure function: same plan + config produces same tool call sequence.

**Schema-validated plans.** Every LLM plan validated against tool registry via Pydantic before invocation.

**Bash is the concurrency primitive.** No threads. No async. Parallelism via processes.

**Zero implicit configuration.** `Config` resolved once at startup, passed explicitly to every function.

**RSI never touches main.** All cycles operate on isolated `rsi/cycle-N` branches. Human merge required.

### Data Flow

```
argv
 -> main()
      |- load_config()            -> Config
      |- make_memory_tools()      -> Tool, Tool
      |- {shell, read_file, ...}  -> registry: dict[str, Tool]
      -> run(task, config, registry)
           |- generate_plan()     -> State (schema-validated)
           |- paranoid audit      -> safe | block
           -> loop over steps
                |- ToolCall -> tool.effect(args) -> Ok | Err -> State
                -> Halt    -> State(status=HALTED)
           -> record_run()        -> ~/.apex/runs.db
```

### Exit Codes

`0` — HALTED. `1` — ERROR. `2` — unexpected terminal state.

---

## Tests

```bash
pytest apex/tests/ -q -m "not live"
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

### Research Swarm

```bash
for i in $(seq 1 4); do
    apex "research aspect $i of '$TOPIC', write findings to ~/research-$i.txt" &
done
wait
apex "read ~/research-1.txt ~/research-2.txt ~/research-3.txt ~/research-4.txt, synthesise into ~/report.txt"
```

---

## Examples

```bash
./examples/autonomous-business.sh ~/.config/apex/business_profile.txt
./examples/code-review.sh ~/myproject "*.py"
./examples/iterative-coder.sh "write a script that finds prime numbers up to N" 8
./examples/research-agent.sh "how does RAFT consensus work" 15
./examples/competitive-intelligence-swarm.sh "Vercel" 5 6
./examples/parallel-swarm.sh "the current state of fusion energy" 5 8
./examples/recursive-self-improvement-swarm.sh 5 ~/c/apps/axiom-apex
```

---

## Templates

`compliance-audit.sh` · `cybersecurity.sh` · `due-diligence.sh` · `healthcare-rcm.sh` · `hedge-fund.sh` · `insurance-claims.sh` · `law-firm.sh` · `msp.sh` · `recruiter.sh` · `revenue-monitor.sh` · `solo-agency.sh` · `supply-chain.sh`

---

## Extending APEX

**1. `apex/tools.py`:**
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
