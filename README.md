# APEX: Agent Process Executor
## Version 1.2
A pure functional CLI agent for deterministic task execution. Built for advanced users who automate everything.

---

## Overview

APEX translates natural language commands into deterministic execution plans using Gemini 2.5 Flash as the planning layer. It executes via a minimal set of shell-centric tools, persists state across sessions via SQLite, and integrates cleanly into bash workflows for multi-step automation, recursive loops, and multi-agent orchestration patterns.

395 lines of core code. Zero runtime configuration. Full Unix toolchain access.

**v1.2 additions:** Validated swarm orchestration, autonomous research agents, iterative 3D asset generation, and character/world generation pipelines.

---

## Features

- **Deterministic execution** — identical inputs produce identical results
- **Natural language interface** — plain English commands translated to tool invocations
- **Shell-centric** — full access to the Unix toolchain via the shell tool
- **SQLite memory** — persistent cross-session state management
- **Minimal footprint** — 395 LOC, no runtime config, no plugin system
- **Bash-composable** — designed to be orchestrated from wrapper scripts
- **espeak integration** — text-to-speech narration of any output
- **Parallel execution** — multiple APEX calls with `&` and `wait`
- **Recursive loops** — self-referential workflows via bash wrappers
- **Multi-agent patterns** — multiple APEX calls sharing a transcript file
- **Swarm orchestration** — parent-directed parallel agent networks with synthesis
- **Autonomous agents** — self-directed SEARCH / THINK / DONE decision loops
- **Iterative asset generation** — code, 3D models, documents evolved across generations

---

## Architecture

```
apex/
├── bin/apex           # CLI entry point
├── core/              # Pure functional execution logic
│   ├── loop.py        # Main execution loop
│   ├── planner.py     # LLM plan generation
│   ├── state.py       # Immutable state management
│   └── types.py       # Type definitions
├── llm/               # LLM provider interface
│   └── providers.py   # Gemini integration
├── tools/             # Effect implementations
│   ├── basic.py       # Core tools (shell, file I/O, HTTP)
│   └── registry.py    # Tool registration
├── memory/            # Persistence layer
│   └── sqlite.py      # SQLite memory operations
└── prompts/           # System prompts
    ├── system.txt     # Core instructions
    └── planner.txt    # Planning guidance
```

Six modules. Strict separation of concerns. The planner generates plans, tools execute effects, state is immutable between steps.

---

## Installation

Requires Python 3.11 or 3.12. **Python 3.14 is not supported** due to pydantic compatibility issues with google-genai.

```bash
git clone https://github.com/axiom-llc/apex.git
cd apex
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

export GEMINI_API_KEY='your-api-key-here'
export PATH="$PATH:$(pwd)/bin"
```

**Critical:** Always run apex from the repository root. The planner resolves `prompts/system.txt` relative to the working directory.

```bash
# Correct
cd ~/code/apex && apex "your command"

# Wrong — will error with FileNotFoundError: prompts/system.txt
~/code/apex/bin/apex "your command"
```

For scripts, add this to the top:
```bash
cd ~/path/to/apex
```

---

## Tools

| Tool | Purpose |
|------|---------|
| `shell` | Execute arbitrary shell commands |
| `read_file` | Read file contents |
| `write_file` | Write content to file |
| `http_get` | HTTP GET via curl |
| `memory_read` | Read from SQLite store |
| `memory_write` | Write to SQLite store |

### Forcing tool selection

The planner sometimes chooses suboptimal tools. Use explicit hints:

```bash
# Force write_file instead of inline Python (avoids syntax errors)
apex "write content to ~/file.txt using write_file"

# Force read_file instead of shell cat
apex "read ~/file.txt using read_file and summarize"
```

---

## Basic Usage

```bash
# File operations
apex "write system info and today's date to ~/report.txt"
apex "read ~/config.json and display its contents"

# HTTP requests — works on static pages, APIs, RSS feeds
# Does NOT work on JS-rendered pages (React, Vue, SPAs)
apex "fetch https://wttr.in/London using curl and save to ~/weather.txt"
apex "fetch https://api.github.com/users/torvalds using curl and save to ~/user.json"

# Data processing
apex "analyze ~/logs/app.log for ERROR lines and count them"
apex "parse ~/data.csv and calculate average of the third column"

# Memory
apex "save current git branch to memory as active_branch"
apex "read from memory the active_branch value"
```

---

## Reliable APIs (No Keys Required)

These work consistently with `http_get`:

| API | Use |
|-----|-----|
| `https://hn.algolia.com/api/v1/search?query=TERM` | HackerNews full-text search |
| `https://en.wikipedia.org/api/rest_v1/page/summary/TOPIC` | Wikipedia page summary |
| `https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=TERM&format=json` | Wikipedia search |
| `https://wttr.in/CITY?format=j1` | Weather as JSON |
| `https://api.github.com/repos/OWNER/REPO` | GitHub repo info |
| `https://api.github.com/search/repositories?q=TERM` | GitHub repo search |

**Avoid:** DuckDuckGo API (returns empty body under load), Wikipedia HTML pages (403 without user-agent).

**Spaces in URLs:** replace with `+` e.g. `srsearch=machine+learning`

---

## Scripting Patterns

APEX is designed to be orchestrated from bash. Single commands are the exception — scripts are the norm.

### Critical: Never inject file contents into apex commands

```bash
# ✗ Breaks on quotes, backslashes, special chars — causes JSON parse errors
apex "here is the file: $(cat file.scad) now improve it"

# ✓ Always tell apex to read files itself
apex "read the file using read_file from file.scad then improve it and write back"
```

### Sequential pipeline

```bash
cd ~/path/to/apex

apex "fetch https://wttr.in/London using curl and write to ~/weather.txt"
apex "read ~/weather.txt using read_file and write a dramatic haiku to ~/haiku.txt"
cat ~/haiku.txt | tr -cd '[:print:][:space:]' | espeak -v en+m3 -p 35 -s 120 -w ~/haiku.wav
aplay ~/haiku.wav
```

### Parallel execution

```bash
apex "write planet report for Mars to ~/mars.txt" &
apex "write planet report for Jupiter to ~/jupiter.txt" &
apex "write planet report for Saturn to ~/saturn.txt" &
wait
apex "use espeak to say all planet reports complete"
```

### Recursive loop with state

```bash
echo "initial state" > ~/state.txt

for i in 1 2 3 4 5; do
    apex "read ~/state.txt using read_file and expand it with new information.
    Write the updated state to ~/state.txt using write_file"
done
```

### Compile-test-fix loop (Convergence pattern)

The foundation for any generated code or structured output:

```bash
for i in $(seq 1 "$ITERATIONS"); do
    if compile_or_test "$OUTPUT" 2>"$LOG"; then
        apex "read ${OUTPUT} using read_file
              read ${LOG} using read_file
              improve the output and write back to ${OUTPUT} using write_file"
    else
        apex "read ${OUTPUT} using read_file
              read ${LOG} using read_file
              fix all errors and write corrected output to ${OUTPUT} using write_file"
    fi
done
```

---

## Autonomous Agent Scripts

### agent.sh — Self-directed research agent

Decides its own actions each step: `SEARCH`, `THINK`, or `DONE`.

```bash
./agent.sh "how does RAFT consensus work" 15
./agent.sh "free"   # agent picks its own topic
```

**Action loop:**
```
agent reads full state → decides action → executes → appends to state → repeat
SEARCH  → picks best API + URL → fetches → extracts signal
THINK   → reasons over accumulated knowledge → notes gaps
DONE    → exits loop early → writes final report
```

**Token budget:** ~2 apex calls per step + 1 synthesis. 8 iterations ≈ 17 calls.

### research.sh — Structured iterative research

Simpler than agent.sh — fixed SEARCH + EXTRACT pattern, no autonomous action selection.

```bash
./research.sh "transformer attention mechanisms" 6
```

### chargen.sh — Iterative character generator

Cycles through dimensions (background, personality, skills) across N passes.

```bash
./chargen.sh "disgraced soldier turned mercenary" 6
./chargen.sh "rogue AI pretending to be human" 9
```

### mechagen.sh — Iterative 3D model generator

Generates OpenSCAD, compiles to STL, feeds errors/success back to agent for improvement.

```bash
./mechagen.sh 6   # 6 refinement iterations
```

Requires: `openscad` (headless). Each iteration saves its own STL — full evolution history.

**Validated results:** 32K → 88K STL growth across 2 iterations in production test.

---

## Swarm Orchestration

### swarm.sh — Core swarm pattern

Parent generates N sub-goals → parallel `agent.sh` calls → parent synthesises all reports.

```bash
./swarm.sh "quantum computing applications" 4 8
./swarm.sh free 2 4    # swarm picks its own topic
#           │   │  └── iterations per agent
#           │   └───── number of parallel agents  
#           └────────── goal or "free"
```

**Call budget:**
```
1  (topic, if free)
1  (sub-goal decomposition)
N × ((iterations × 2) + 1)  (agents)
1  (synthesis)
```
With `4 agents, 8 iter`: up to ~71 calls. Start with `2 4` (~20 calls) to validate.

**Recommended starting values:**

| Use case | agents | iter |
|----------|--------|------|
| Quick test | 2 | 4 |
| Normal run | 4 | 8 |
| Deep research | 6 | 12 |

**Validated production run:** 3 parallel agents researching quantum ML, quantum entanglement comms, and DAOs in research funding. Agents 1 and 2 completed with 4908 and 5362 byte reports respectively.

**Known issue:** DDG API returns empty body under load — use HN Algolia and Wikipedia summary instead. Wikipedia HTML returns 403 without user-agent — use the REST API endpoints only.

### Monitor a swarm run

```bash
# Watch files appear in real time
watch -n2 'find ~/swarm -name "*.txt" -o -name "*.md" | head -20'

# Follow a specific agent
tail -f ~/swarm/TIMESTAMP/agent_0/state.txt
```

---

## espeak Integration

```bash
# Basic narration
apex "read ~/report.txt and use espeak to read it aloud"

# Voice, pitch, speed control
apex "read ~/report.txt and use espeak with voice en+m3 pitch 35 speed 130 and save to ~/report.wav"
```

**Handling special characters:**
```bash
cat file.txt | tr -cd '[:print:][:space:]' | espeak -v en+m3 -p 35 -s 130 -w output.wav
```

---

## Output Pipeline

APEX-generated content renders to multiple formats via standard Unix tools:

```bash
# Markdown → HTML
pandoc report.md -o page.html --standalone

# Markdown → PDF
pandoc report.md -o report.pdf --pdf-engine=wkhtmltopdf

# SVG → PDF (print-ready)
inkscape poster.svg --export-pdf=poster.pdf

# OpenSCAD → STL (3D printable)
openscad -o model.stl model.scad

# Sync to object storage
rclone sync ~/output r2:your-bucket/run-name
```

---

## Known Planner Behaviors

**Inline Python syntax errors** — Always use `write_file` explicitly:
```bash
# Reliable
apex "write a python script to ~/calc.py using write_file then run it with python3"
```

**File content injection** — Never use `$(cat file)` in apex commands. Tell apex to use `read_file` instead.

**Hallucinated commands** — Specify tools explicitly to prevent invented shell commands.

**Cascading failures** — If step 1 fails to write a file, step 2 fails to read it. Check output files exist before proceeding.

**Empty API responses** — DDG and some Wikipedia endpoints return empty under certain conditions. Always guard:
```bash
if [[ ! -f "$OUTPUT" ]]; then
    echo "⚠ skipping — no output written"
    continue
fi
```

**Agent looping** — If an agent's searches return empty, it may re-issue the same query repeatedly. Mitigate by restricting APIs to known-reliable endpoints (HN, Wikipedia REST).

---

## Performance

| Operation | Typical duration |
|-----------|----------------|
| Plan generation | 100–500ms |
| File read/write | < 100ms |
| Shell command | < 5s typical |
| HTTP GET | Network-dependent |
| SQLite read/write | < 10ms |
| OpenSCAD compile | 1–30s depending on complexity |
| espeak WAV generation | 1–10s depending on length |

Token consumption per call: approximately 1,000–4,000 tokens depending on task complexity.

---

## Constraints

| Constraint | Value |
|-----------|-------|
| Max plan steps | 32 |
| Tool timeout | 300 seconds |
| Max tool output | 10 MB |
| Inter-step state passing | Not supported (use flat files) |
| Conditional branching in plans | Not supported (use bash) |
| Browser automation | Not supported |
| JS-rendered page scraping | Not supported |

---

## Production Use

Validated for:
- Cron-driven business automation
- Multi-client MSP monitoring
- Content generation pipelines
- System health monitoring and narrated briefings
- Multi-agent conversation and debate scripts
- Recursive self-improving document generation
- Autonomous research loops with self-directed action selection
- Parallel swarm research with synthesis
- Iterative 3D model generation (OpenSCAD → STL)
- Iterative character and world generation for creative pipelines

Not suitable for:
- Interactive real-time applications
- Browser automation
- Multi-user systems without additional isolation
- Real-time event processing
- Tasks requiring vision or image understanding

---

## Design Principles

Functional purity in the core. All effects isolated to tools. Immutable state via `dataclasses.replace()`. No dynamic configuration. No plugin discovery. No runtime extension.

Inspired by [suckless](https://suckless.org/) and [Arch Linux](https://archlinux.org/) design philosophy: do one thing, do it well, expose everything, hide nothing.

---

## License

MIT

---

## Credits

APEX is developed by [Axiom-LLC](https://github.com/axiom-llc).

---

**Status**: Production-ready v1.2 | Swarm orchestration validated | Autonomous agents validated | 3D asset generation validated | Multi-format output pipeline validated
