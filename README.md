[![PyPI](https://img.shields.io/pypi/v/axiom-apex.svg)](https://pypi.org/project/axiom-apex/)
# APEX — Agentic Process Executor

**v2.0.0** · Pure-functional CLI framework for deterministic, reproducible AI-driven workflows. Python 3.11+ · Gemini 2.5 Flash · MIT

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

`apex` is available globally within the activated environment. No PATH configuration required.

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

**`--interactive`**, **`-i`** — Enter interactive prompt mode. Accept tasks one at a time without re-invoking the CLI. `exit` or Ctrl-D to quit.
```bash
apex -i
# APEX 2.0.0 — interactive mode. Ctrl-D or 'exit' to quit.
# apex> write today's date to ~/date.txt
# apex> exit
```

**`--dry-run`** — Generate and print the execution plan as JSON. No tools are invoked.
```bash
apex --dry-run "fetch https://wttr.in/London and save to ~/weather.txt"
```
```json
{
  "goal": "Fetch weather data for London and save to ~/weather.txt",
  "steps": [
    {"type": "tool", "name": "shell", "args": {"cmd": "curl -s https://wttr.in/London > ~/weather.txt"}},
    {"type": "halt", "reason": "done"}
  ]
}
```

**`--trace`** — Stream each step result to stderr during execution.
```bash
apex --trace "write the current date to ~/date.txt"
# [plan] goal=Write current date to ~/date.txt status=RUNNING
# [tool] shell args={'cmd': 'date > ~/date.txt'}
# [result] ok
# [halt] done
```

**`--full-trace`** — Write structured JSONL trace events to file or stderr. Each event includes a timestamp and full step context.
```bash
apex --full-trace "write the current date to ~/date.txt"
apex --full-trace --trace-path ~/traces/run.jsonl "write the current date to ~/date.txt"
```

**`--trace-path <path>`** — Path to JSONL trace output file. Used with `--full-trace`. Defaults to stderr if omitted.

**`--version`** — Print version and exit.

---

## Swarm Mode

Run multiple independent tasks in parallel with optional human-in-loop confirmation.

```bash
apex swarm --tasks tasks.json --workers 4
apex swarm --tasks tasks.json --workers 4 --human-loop
apex swarm --tasks tasks.json --workers 4 --trace-path ~/traces/swarm.jsonl
```

`tasks.json` — array of task prompt strings:
```json
[
  "write planet report for Mars to ~/mars.txt",
  "write planet report for Jupiter to ~/jupiter.txt",
  "write planet report for Saturn to ~/saturn.txt"
]
```

`--human-loop` pauses for confirmation before each batch. `--workers` caps concurrent apex processes (recommended ceiling: 4 for Gemini 2.5 Flash).

---

## Tools

**`shell`** `cmd: str` — Execute a shell command. Returns stdout, stderr, and exit code.

**`read_file`** `path: str` — Read file contents.

**`write_file`** `path: str, content: str` — Write to file. Creates parent directories as needed.

**`http_get`** `url: str, headers?: dict` — HTTP GET via requests. Returns body and status code.

**`rag_multi_query`** `queries: list[str], top_k?: int` — Multi-hop semantic retrieval via axiom-rag. Issues multiple queries against the local ChromaDB collection and returns merged, deduplicated results. Requires axiom-rag installed and a collection ingested.

**`memory_read`** `key?: str` — Read a named value from persistent memory. Omit `key` to list all entries.

**`memory_write`** `key: str, value: any` — Write a JSON-serialisable value to persistent memory.

### Memory

Memory is backed by SQLite at `~/.apex/memory.db` and persists across invocations and concurrent processes.

---

## Configuration

**`GEMINI_API_KEY`** *(required)* — Gemini API key. APEX exits immediately without it.

**`APEX_DB_PATH`** *(optional, default: `~/.apex/memory.db`)* — SQLite memory database path.

**`LLM_PROVIDER`** *(optional, default: `gemini`)* — LLM backend. Set to `ollama` to use a local Ollama instance. When set to `ollama`, `GEMINI_API_KEY` is not required.

```bash
LLM_PROVIDER=ollama apex "write today's date to ~/date.txt"
```

---

## Architecture

```
apex/
  __main__.py     <- CLI entry; builds registry, calls run()
  config.py       <- Frozen Config dataclass, resolved once at startup
  llm.py          <- Gemini + Ollama adapters (stateless)
  memory.py       <- make_memory_tools(db_path) -> (memory_read, memory_write)
  tools.py        <- shell, read_file, write_file, http_get, rag_multi_query
  prompt.txt      <- System + planner prompt
  bench.py        <- Task benchmark harness
  benchmarks/
    tasks.json    <- Default benchmark task definitions
    results/      <- CI and local benchmark output JSONs
  core/
    types.py      <- Frozen dataclasses: Plan, Step, Result, Tool, Event
    state.py      <- Immutable State; format_output
    planner.py    <- Prompt rendering, JSON plan parsing, Pydantic schema validation
    loop.py       <- Pure run(task, config, registry) -> State
    trace.py      <- JSONL write_event
    swarm.py      <- Parallel swarm coordinator with human-in-loop
```

### Design Axioms

**Immutability.** All core types are frozen dataclasses. `State` is updated via `dataclasses.replace()` — never mutated in place.

**Pure execution loop.** `run()` in `core/loop.py` is a pure function: same plan + same config produces same tool call sequence.

**Schema-validated plans.** Every LLM-generated plan is validated against the tool registry via Pydantic before any tool is invoked.

**Bash is the concurrency primitive.** No threads. No async. Parallelism via multiple `apex` processes under bash or `apex swarm`.

**Zero implicit configuration.** `Config` is resolved once at startup, validated immediately, passed explicitly to every function.

**Memory tools are closures.** `make_memory_tools(db_path)` returns tool instances whose effects close over `db_path`.

### Data Flow
```
argv
 -> main()
      |- load_config()            -> Config
      |- make_memory_tools()      -> Tool, Tool
      |- {shell, read_file, ...}  -> registry: dict[str, Tool]
      -> run(task, config, registry)
           |- generate_plan()     -> State (plan attached, schema-validated)
           -> loop over steps
                |- ToolCall -> tool.effect(args) -> Ok | Err -> State
                -> Halt    -> State(status=HALTED)
```

### Exit Codes

`0` — HALTED. `1` — ERROR. `2` — unexpected terminal state.

---

## Tests

```bash
pytest apex/tests/ -q -m "not live"
```

CI runs the non-live suite on Python 3.11 and 3.12 on every push.

### Benchmark Harness

```bash
python apex/bench.py --tasks apex/benchmarks/tasks.json --mock
python apex/bench.py --tasks apex/benchmarks/tasks.json
python apex/bench.py --tasks apex/benchmarks/tasks.json --out apex/benchmarks/results/run.json
```

`--mock` skips real apex calls — safe for CI without `GEMINI_API_KEY`. CI uploads results as a build artifact.

`tasks.json` schema:
```json
[
  {
    "id": "write_file",
    "prompt": "write 'hello' to /tmp/apex-bench-out.txt",
    "check": "hello",
    "check_file": "/tmp/apex-bench-out.txt"
  }
]
```

---

## Scripting & Parallelism

### Parallel Tasks

```bash
apex "write planet report for Mars to ~/mars.txt" &
apex "write planet report for Jupiter to ~/jupiter.txt" &
wait
```

**Concurrency ceiling — Gemini 2.5 Flash:** practical ceiling of **4 concurrent processes**.

| tasks | concurrency | sequential | parallel | speedup | efficiency |
|-------|-------------|-----------|----------|---------|------------|
| 4 | 4 (uncapped) | 22.64s | 7.60s | 2.98x | 0.75 |
| 8 | uncapped | 45.08s | 12.07s | 3.74x | 0.47 |
| 8 | 4 (batched) | 44.23s | 22.36s | 1.98x | 0.25 |

### Iterative Fix Loop
```bash
OUTPUT=~/solution.py
LOG=~/build.log

for i in $(seq 1 "$ITERATIONS"); do
    python3 "$OUTPUT" 2>"$LOG" && break
    apex "read ${OUTPUT}, read ${LOG}, fix all errors and write back to ${OUTPUT}"
done
```

### Research Swarm
```bash
TOPIC="distributed systems consistency models"
AGENTS=4

for i in $(seq 1 "$AGENTS"); do
    apex "research aspect $i of '$TOPIC', write findings to ~/research-$i.txt" &
done
wait

apex "read ~/research-1.txt ~/research-2.txt ~/research-3.txt ~/research-4.txt, synthesise into ~/report.txt"
```

---

## Examples

Runnable demonstrations in `examples/` covering single-agent loops, iterative refinement, and multi-agent parallel swarms.

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

Production-ready integration templates in `templates/` for common operational contexts.

`compliance-audit.sh` · `cybersecurity.sh` · `due-diligence.sh` · `healthcare-rcm.sh` · `hedge-fund.sh` · `insurance-claims.sh` · `law-firm.sh` · `msp.sh` · `recruiter.sh` · `revenue-monitor.sh` · `solo-agency.sh` · `supply-chain.sh`

---

## Extending APEX

Add a tool by touching three files:

**1. `apex/tools.py`:**
```python
def list_dir_effect(args: dict) -> dict:
    from pathlib import Path
    items = list(Path(args["path"]).iterdir())
    return {"items": [str(i) for i in items], "count": len(items)}

LIST_DIR = Tool(
    name="list_dir",
    input_spec={"path": str},
    output_spec={"items": list, "count": int},
    effect=list_dir_effect,
)
```

**2. `apex/__main__.py`:**
```python
registry: dict[str, Tool] = {
    "shell": SHELL,
    "list_dir": LIST_DIR,
}
```

**3. `apex/prompt.txt`:**
```
- list_dir: list directory contents. args: {path}. returns: {items, count}
```

---

## Constraints

- Max plan steps: 32
- Tool timeout: 300 seconds
- Max tool output: 10 MB
- LLM provider: Gemini 2.5 Flash (default) or Ollama (local)
- Concurrency: bash process isolation; recommended ceiling: **4 concurrent processes**
- Platform: Unix (SIGALRM-based timeout)

---

## License

MIT — [AXIOM LLC](https://axiom-llc.github.io)
