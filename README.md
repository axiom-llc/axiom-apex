# APEX — Agent Process Executor

Pure-functional CLI framework for deterministic, reproducible AI-driven workflows.

```bash
export GEMINI_API_KEY=your-key
apex "analyse this codebase and produce a refactoring plan"
```

---

## Installation

Requires Python 3.11–3.13.

```bash
git clone https://github.com/axiom-llc/apex.git ~/code/apps/apex
cd ~/code/apps/apex
python3.12 -m venv venv && source venv/bin/activate
pip install -e .
```

`apex` is available as a command anywhere after install. No PATH configuration required.

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

**`--dry-run`** — Generate and print the execution plan as JSON without running any tools.

```bash
apex --dry-run "fetch https://wttr.in/London and save to ~/weather.txt"
```

```json
{
  "goal": "Fetch weather data for London and save to ~/weather.txt",
  "steps": [
    {"type": "tool", "name": "shell", "args": {"cmd": "curl -s https://wttr.in/London > /home/user/weather.txt"}},
    {"type": "halt", "reason": "done"}
  ]
}
```

**`--trace`** — Stream each step's result to stderr as execution proceeds.

```bash
apex --trace "write the current date to ~/date.txt"
# [plan] goal=Write current date to ~/date.txt status=RUNNING
# [tool] shell args={'cmd': 'date > /home/user/date.txt'}
# [result] ok
# [halt] done
```

**`--version`** — Print version and exit.

---

## Tools

**`shell`** `cmd: str` — Execute a shell command. Returns stdout, stderr, and exit code. Prefer this for any operation expressible as a single command; use pipes, redirects, and `&&`/`||` to combine steps.

**`read_file`** `path: str` — Read the contents of a file.

**`write_file`** `path: str, content: str` — Write content to a file. Creates parent directories as needed.

**`http_get`** `url: str, headers?: dict` — HTTP GET via requests. Returns body and status code. Does not support JS-rendered pages.

**`memory_read`** `key?: str` — Read a named value from persistent memory. Omit `key` to return all entries.

**`memory_write`** `key: str, value: any` — Write a named value to persistent memory. Accepts any JSON-serialisable value.

### Memory

Memory is backed by a local SQLite database (`~/.apex/memory.db` by default) and persists across invocations and across parallel processes.

```bash
apex "save current git branch to memory as active_branch"
apex "read from memory the key active_branch"
```

---

## Configuration

**`GEMINI_API_KEY`** *(required)* — Gemini API key. APEX will not start without it.

**`APEX_DB_PATH`** *(optional, default: `~/.apex/memory.db`)* — Path to the SQLite memory database.

---

## Architecture

APEX is a pure-functional pipeline. Every stage is a transformation over immutable frozen dataclasses — no shared mutable state, no hidden side-channels.

```
apex/
  __main__.py     ← CLI entry; builds registry, calls run()
  config.py       ← Frozen Config dataclass, resolved once at startup
  llm.py          ← Gemini adapter (no global state)
  memory.py       ← make_memory_tools(db_path) → (memory_read, memory_write)
  tools.py        ← shell, read_file, write_file, http_get
  prompt.txt      ← System + planner prompt
  core/
    types.py      ← Frozen dataclasses: Plan, Step, Result, Tool, Event
    state.py      ← Immutable State; format_output
    planner.py    ← Prompt rendering, JSON plan parsing, plan validation
    loop.py       ← Pure run(input, config, registry) → State
```

### Design axioms

**Immutability.** All core types are frozen dataclasses. `State` is never mutated in place — every operation returns a new `State` via `dataclasses.replace`.

**Pure execution loop.** `run()` in `core/loop.py` is a pure function: given the same plan and config it produces the same sequence of tool calls. Side effects are isolated to tool `effect` functions.

**Bash is the concurrency primitive.** APEX does not use threads or async. Parallelism is achieved by running multiple `apex` processes concurrently under bash. Each invocation is a fully isolated process with its own LLM context and state.

**Zero implicit configuration.** Config is resolved once at startup from environment variables, validated immediately, and passed explicitly to every function that needs it. No globals, no module-level singletons.

**Memory tools are closures, not globals.** `make_memory_tools(db_path)` returns tool instances whose effect functions close over `db_path`. The database path is bound at construction time — no startup ordering dependency possible.

### Data flow

```
argv
 └─ main()
      ├─ load_config()           → Config
      ├─ make_memory_tools()     → Tool, Tool
      ├─ {shell, read_file, ...} → registry: dict[str, Tool]
      └─ run(task, config, registry)
           ├─ generate_plan()    → State (plan attached)
           └─ loop over steps
                ├─ ToolCall → tool.effect(args) → Ok | Err → State
                └─ Halt    → State(status=HALTED)
```

### Exit codes

`0` — plan completed (`HALTED`). `1` — execution error (`ERROR`). `2` — unexpected terminal state.

---

## Scripting & Parallelism

### Parallel tasks

Each `apex` invocation is an isolated process. Run them concurrently with bash `&` and `wait`:

```bash
apex "write planet report for Mars to ~/mars.txt" &
apex "write planet report for Jupiter to ~/jupiter.txt" &
wait
```

### Iterative fix loop

```bash
OUTPUT=~/solution.py
LOG=~/build.log

for i in $(seq 1 "$ITERATIONS"); do
    if python3 "$OUTPUT" 2>"$LOG"; then
        break
    else
        apex "read ${OUTPUT}, read ${LOG}, fix all errors and write back to ${OUTPUT}"
    fi
done
```

### Research swarm

```bash
TOPIC="quantum computing"
AGENTS=4

for i in $(seq 1 "$AGENTS"); do
    apex "research aspect $i of '$TOPIC', write findings to ~/research-$i.txt" &
done
wait

apex "read ~/research-1.txt ~/research-2.txt ~/research-3.txt ~/research-4.txt, synthesise into ~/report.txt"
```

---

## Constraints

- Max plan steps: 32
- Tool timeout: 300 seconds
- Max tool output: 10 MB
- LLM provider: Gemini 2.5 Flash
- Concurrency: bash (`&` / `wait`) only
- Platform: Unix (timeout is SIGALRM-based)
- JS-rendered pages: not supported

---

## License

MIT — [Axiom LLC](https://axiom-llc.github.io)
