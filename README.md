# APEX — Agent Process Executor
**v1.2** · Pure-functional CLI framework for deterministic, reproducible AI-driven workflows.

```bash
export GEMINI_API_KEY=your-key
apex "analyse this codebase and produce a refactoring plan"
```

---

## Design

- **Pure-functional core** — immutable state, no side effects in the execution loop
- **JSON-plan orchestration** — structured, inspectable execution traces
- **SQLite KV memory** — persistent agent state across sessions
- **Zero runtime config** — one environment variable, no plugin system
- **395 LOC** — readable, auditable, forkable
- **Bash-composable** — designed to be orchestrated from wrapper scripts

---

## Structure

```
bin/            ← CLI entry point
core/           ← loop.py, planner.py, state.py, types.py
llm/            ← Gemini API integration
memory/         ← SQLite KV store
prompts/        ← system.txt, planner.txt
templates/      ← business process workflows (medical, dental, retail, logistics…)
tools/          ← basic.py (shell, file I/O, HTTP), registry.py
examples/       ← research-agent.sh, research-swarm.sh
docs/
tests/
```

---

## Installation

Requires Python 3.11 or 3.12. Python 3.14 is not supported (pydantic/google-genai compatibility).

```bash
git clone https://github.com/axiom-llc/apex.git
cd apex
python3.12 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
export GEMINI_API_KEY=your-key
export PATH="$PATH:$(pwd)/bin"
```

**Always run apex from the repo root** — the planner resolves `prompts/system.txt` relative to the working directory.

```bash
# Correct
cd ~/apex && apex "task"

# Wrong — FileNotFoundError: prompts/system.txt
~/apex/bin/apex "task"
```

---

## Tools

| Tool | Purpose |
|---|---|
| `shell` | Execute arbitrary shell commands |
| `read_file` | Read file contents |
| `write_file` | Write content to file |
| `http_get` | HTTP GET via curl |
| `memory_read` | Read from SQLite store |
| `memory_write` | Write to SQLite store |

Force tool selection when the planner chooses suboptimally:

```bash
apex "write content to ~/file.txt using write_file"
apex "read ~/file.txt using read_file and summarize"
```

---

## Usage

```bash
# File operations
apex "write system info and today's date to ~/report.txt"

# HTTP — works on static pages, REST APIs, RSS feeds
# Does NOT work on JS-rendered pages (React, Vue, SPAs)
apex "fetch https://wttr.in/London using curl and save to ~/weather.txt"
apex "fetch https://api.github.com/users/torvalds using curl and save to ~/user.json"

# Data processing
apex "analyse ~/logs/app.log for ERROR lines and count them"

# Memory
apex "save current git branch to memory as active_branch"
apex "read from memory the active_branch value"
```

### Reliable public APIs (no keys required)

| API | Use |
|---|---|
| `https://hn.algolia.com/api/v1/search?query=TERM` | HackerNews search |
| `https://en.wikipedia.org/api/rest_v1/page/summary/TOPIC` | Wikipedia summary |
| `https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=TERM&format=json` | Wikipedia search |
| `https://wttr.in/CITY?format=j1` | Weather JSON |
| `https://api.github.com/repos/OWNER/REPO` | GitHub repo info |

**Avoid:** DuckDuckGo API (returns empty body under load), Wikipedia HTML pages (403 without user-agent). Replace spaces with `+` in all URLs.

---

## Scripting Patterns

**Never inject file contents into apex commands:**

```bash
# ✗ Breaks on quotes, backslashes — causes JSON parse errors
apex "here is the file: $(cat file.scad) improve it"

# ✓ Tell apex to read the file itself
apex "read file.scad using read_file then improve it and write back"
```

### Parallel execution

```bash
apex "write planet report for Mars to ~/mars.txt" &
apex "write planet report for Jupiter to ~/jupiter.txt" &
wait
```

### Compile-test-fix loop

```bash
for i in $(seq 1 "$ITERATIONS"); do
    if compile_or_test "$OUTPUT" 2>"$LOG"; then
        apex "read ${OUTPUT} using read_file, read ${LOG} using read_file,
              improve output and write back to ${OUTPUT} using write_file"
    else
        apex "read ${OUTPUT} using read_file, read ${LOG} using read_file,
              fix all errors and write corrected output to ${OUTPUT} using write_file"
    fi
done
```

---

## Examples

See [`examples/`](./examples/) for:

- **`research-agent.sh`** — autonomous SEARCH/THINK/DONE research loop with self-directed action selection
- **`research-swarm.sh`** — parallel swarm orchestration: N agents research sub-goals, parent synthesises

```bash
./examples/research-agent.sh "how does RAFT consensus work" 15
./examples/research-swarm.sh "quantum computing" 4 8
```

Validated production runs: swarm orchestration with 3 parallel agents, iterative 3D asset generation (OpenSCAD → STL, 32K → 88K across 2 iterations).

---

## Constraints

| Constraint | Value |
|---|---|
| Max plan steps | 32 |
| Tool timeout | 300s |
| Max tool output | 10MB |
| Inter-step state passing | Via flat files only |
| Conditional branching | Via bash, not plans |
| Browser/JS-rendered pages | Not supported |

---

## Known Planner Behaviors

- **Inline Python errors** — always use `write_file` explicitly for scripts
- **Cascading failures** — if step 1 fails to write a file, step 2 fails to read it; guard with `[[ -f "$FILE" ]]`
- **Empty API responses** — guard all fetch steps; DDG is unreliable under load
- **Agent looping** — restrict to known-reliable APIs to prevent repeated failed queries

---

## Performance

| Operation | Typical |
|---|---|
| Plan generation | 100–500ms |
| File read/write | < 100ms |
| SQLite read/write | < 10ms |
| HTTP GET | Network-dependent |
| OpenSCAD compile | 1–30s |

Token consumption: ~1,000–4,000 per call depending on task complexity.

---

## Design Philosophy

Functional purity in the core. All effects isolated to tools. Immutable state via `dataclasses.replace()`. No dynamic configuration. No plugin discovery.

Inspired by [suckless](https://suckless.org/) and [Arch Linux](https://archlinux.org/) philosophy: do one thing well, expose everything, hide nothing.

---

## License

MIT — [Axiom LLC](https://axiom-llc.github.io)
