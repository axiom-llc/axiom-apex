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
git clone https://github.com/axiom-llc/axiom-apex.git ~/code/apps/axiom-apex
cd ~/code/apps/axiom-apex
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
# APEX 1.0.0 — interactive mode. Ctrl-D or 'exit' to quit.
# apex> write today's date to ~/date.txt
# apex> fetch https://wttr.in/London and save to ~/weather.txt
# apex> exit
```

Each prompt runs a full independent plan-generate → execute cycle. Sessions are stateless across prompts — consistent with single-shot invocation behaviour.

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

**`--trace`** — Stream each step's result to stderr during execution.
```bash
apex --trace "write the current date to ~/date.txt"
# [plan] goal=Write current date to ~/date.txt status=RUNNING
# [tool] shell args={'cmd': 'date > ~/date.txt'}
# [result] ok
# [halt] done
```

**`--version`** — Print version and exit.

---

## Tools

**`shell`** `cmd: str` — Execute a shell command. Returns stdout, stderr, and exit code. Use pipes, `&&`, and `||` to compose multi-step operations into a single invocation.

**`read_file`** `path: str` — Read file contents.

**`write_file`** `path: str, content: str` — Write to file. Creates parent directories as needed.

**`http_get`** `url: str, headers?: dict` — HTTP GET via requests. Returns body and status code. Does not support JS-rendered pages.

**`memory_read`** `key?: str` — Read a named value from persistent memory. Omit `key` to list all entries.

**`memory_write`** `key: str, value: any` — Write a JSON-serialisable value to persistent memory.

### Memory

Memory is backed by SQLite at `~/.apex/memory.db` and persists across invocations and concurrent processes.
```bash
apex "save current git branch to memory as active_branch"
apex "read from memory the key active_branch"
```

---

## Configuration

**`GEMINI_API_KEY`** *(required)* — Gemini API key. APEX exits immediately without it.

**`APEX_DB_PATH`** *(optional, default: `~/.apex/memory.db`)* — SQLite memory database path.

---

## Architecture

APEX is a pure-functional pipeline over immutable frozen dataclasses. No shared mutable state. No globals. No module-level singletons.
```
apex/
  __main__.py     ← CLI entry; builds registry, calls run()
  config.py       ← Frozen Config dataclass, resolved once at startup
  llm.py          ← Gemini adapter (stateless)
  memory.py       ← make_memory_tools(db_path) → (memory_read, memory_write)
  tools.py        ← shell, read_file, write_file, http_get
  prompt.txt      ← System + planner prompt
  core/
    types.py      ← Frozen dataclasses: Plan, Step, Result, Tool, Event
    state.py      ← Immutable State; format_output
    planner.py    ← Prompt rendering, JSON plan parsing, Pydantic schema validation
    loop.py       ← Pure run(task, config, registry) → State
```

### Design Axioms

**Immutability.** All core types are frozen dataclasses. `State` is updated via `dataclasses.replace()` — never mutated in place.

**Pure execution loop.** `run()` in `core/loop.py` is a pure function: same plan + same config → same tool call sequence. Side effects are isolated to tool `effect` functions.

**Schema-validated plans.** Every plan generated by the LLM is validated against the tool registry via Pydantic before any tool is invoked. Malformed or unknown-tool plans are rejected at the boundary — execution never begins on an invalid plan.

**Bash is the concurrency primitive.** No threads. No async. Parallelism is achieved by running multiple `apex` processes concurrently under bash. Each invocation is a fully isolated process with its own LLM context and state.

**Zero implicit configuration.** `Config` is resolved once at startup from environment variables, validated immediately, and passed explicitly to every function. No globals, no startup ordering dependencies.

**Memory tools are closures.** `make_memory_tools(db_path)` returns tool instances whose effects close over `db_path`. Database path is bound at construction — no ordering dependency possible.

### Data Flow
```
argv
 └─ main()
      ├─ load_config()            → Config
      ├─ make_memory_tools()      → Tool, Tool
      ├─ {shell, read_file, ...}  → registry: dict[str, Tool]
      └─ run(task, config, registry)
           ├─ generate_plan()     → State (plan attached, schema-validated)
           └─ loop over steps
                ├─ ToolCall → tool.effect(args) → Ok | Err → State
                └─ Halt    → State(status=HALTED)
```

### Exit Codes

`0` — plan completed (`HALTED`). `1` — execution error (`ERROR`). `2` — unexpected terminal state.

---

## Tests

```bash
pytest tests/ -q -m "not live"
```

Tests marked `live` require a valid `GEMINI_API_KEY` and make real API calls. All other tests run without network access. CI runs the non-live suite on Python 3.11 and 3.12 on every push.

---

## Scripting & Parallelism

### Parallel Tasks

Each `apex` invocation is an isolated process. Run concurrently with bash `&` and `wait`:
```bash
apex "write planet report for Mars to ~/mars.txt" &
apex "write planet report for Jupiter to ~/jupiter.txt" &
wait
```

**Concurrency ceiling — Gemini 2.5 Flash:** Empirical benchmarking (see `apex/benchmarks/`) shows a practical ceiling of **4 concurrent processes**. Beyond this, Gemini API request queuing degrades returns significantly.

| tasks | concurrency | sequential | parallel | speedup | efficiency |
|-------|-------------|-----------|----------|---------|------------|
| 4 | 4 (uncapped) | 22.64s | 7.60s | 2.98× | 0.75 |
| 8 | uncapped | 45.08s | 12.07s | 3.74× | 0.47 |
| 8 | 4 (batched) | 44.23s | 22.36s | 1.98× | 0.25 |

For workloads with ≤4 tasks, run uncapped. For >4 tasks, batching to 4 enforces rate-limit safety at the cost of wall-clock time — choose based on whether throughput or compliance is the priority.

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

Runnable demonstrations in `examples/` covering single-agent loops, iterative refinement, and multi-agent parallel swarms. Each script is self-contained and requires only `apex` and `GEMINI_API_KEY`. See `examples/README.md` for full usage and output details.

### Agents
```bash
./examples/autonomous-business.sh ~/.config/apex/business_profile.txt
./examples/code-review.sh ~/myproject "*.py"
./examples/iterative-coder.sh "write a script that finds prime numbers up to N" 8
./examples/research-agent.sh "how does RAFT consensus work" 15
```

### Swarms
```bash
./examples/competitive-intelligence-swarm.sh "Vercel" 5 6
./examples/parallel-swarm.sh "the current state of fusion energy" 5 8
./examples/recursive-self-improvement-swarm.sh 5 ~/code/apps/axiom-apex
```

---

## Templates

Production-ready integration templates in `templates/` for common operational contexts. Each is a self-contained bash script with a command router and cron schedule. Configure the variables at the top and run.

**`compliance-audit.sh`** — Automated compliance audit pipeline. Policy checks, evidence collection, gap analysis, and audit report generation.

**`cybersecurity.sh`** — Security operations. Threat monitoring, log analysis, vulnerability triage, and incident response drafts.

**`due-diligence.sh`** — Investment due diligence. Company research, financial signal extraction, risk scoring, and summary report generation.

**`healthcare-rcm.sh`** — Healthcare revenue cycle management. Claims processing, denial triage, follow-up scheduling, and billing summaries. Local only — no cloud transmission.

**`hedge-fund.sh`** — Hedge fund operations. Market data ingestion, signal generation, portfolio snapshots, and daily briefings.

**`insurance-claims.sh`** — Insurance claims processing. Intake classification, fraud signal detection, adjuster notes, and status tracking.

**`law-firm.sh`** — Law firm. Matter intake, billing entry, deadline tracking, daily briefs, weekly reviews.

**`msp.sh`** — IT managed services. Per-client health checks, incident management, SLA tracking, nightly security audits, client reports.

**`recruiter.sh`** — Recruiting operations. Candidate intake, screening summaries, pipeline tracking, and outreach drafts.

**`revenue-monitor.sh`** — Micro-SaaS uptime monitoring service. Per-client health pulses, downtime alerts, weekly reports, monthly invoicing.

**`solo-agency.sh`** — Solo freelance agency. Project intake, proposal generation, client follow-ups, and invoicing.

**`supply-chain.sh`** — Supply chain operations. Supplier monitoring, inventory alerts, reorder triggers, and risk summaries.

---

## Extending APEX

Add a tool by touching three files:

**1. Define the effect in `apex/tools.py`:**
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

**2. Register in `apex/__main__.py`:**
```python
from apex.tools import SHELL, READ_FILE, WRITE_FILE, HTTP_GET, LIST_DIR

registry: dict[str, Tool] = {
    "shell": SHELL,
    "list_dir": LIST_DIR,
    # ...
}
```

**3. Document in `apex/prompt.txt`:**
```
- list_dir: list directory contents. args: {path}. returns: {items, count}
```

The LLM uses the prompt entry to plan with the tool; the registry entry makes it executable.

---

## Constraints

- Max plan steps: 32
- Tool timeout: 300 seconds
- Max tool output: 10 MB
- LLM provider: Gemini 2.5 Flash
- Concurrency: bash process isolation (`&` / `wait`); recommended ceiling: **4 concurrent processes** (Gemini 2.5 Flash rate limit)
- Platform: Unix (SIGALRM-based timeout)
- JS-rendered pages: not supported

---

## License

MIT — [AXIOM LLC](https://axiom-llc.github.io)
