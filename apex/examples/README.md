# Examples

Runnable demonstrations of [APEX](https://github.com/axiom-llc/axiom-apex) capabilities.
Each script is self-contained — no additional frameworks required beyond `apex` and `GEMINI_API_KEY`.

## Prerequisites

```bash
export GEMINI_API_KEY=your-key
```

Optional, required by specific examples:
```bash
sudo apt install espeak-ng   # spoken audio output
```

---

## Agents

Single-agent loops with autonomous decision-making and iterative refinement.

---

### `autonomous-business.sh`
A complete operating day, unattended. Ingests overnight inbound, triages and classifies, generates a prioritised action plan, executes across four parallel workstreams — lead qualification, pipeline follow-up, project delivery checks, invoice chasing — dispatches proposals for qualified leads, and produces an EOD operating report with a P&L snapshot. No human in the loop.

```bash
./examples/autonomous-business.sh ~/.config/apex/business_profile.txt
./examples/autonomous-business.sh   # uses built-in default profile
```

Output → `~/business/YYYYMMDD/`
- `decisions/daily-plan.txt` — prioritised action plan generated at open
- `comms/inbound-responses-DATE.txt` — drafted responses to inbound items
- `leads/pipeline-actions-DATE.txt` — qualification assessments and follow-ups
- `proposals/proposals-DATE.txt` — proposals generated for qualified leads
- `projects/client-updates-DATE.txt` — proactive client status updates
- `invoices/follow-ups-DATE.txt` — payment follow-ups by age tier
- `eod-report.md` — full operating report
- `pnl-snapshot.txt` — receivables, pipeline value, 30-day forecast

---

### `code-review.sh`
Multi-pass code review agent. Analyses a codebase across three sequential layers — correctness, security, and quality — producing per-file annotations and a consolidated review report with severity-ranked findings and a refactor roadmap.

```bash
./examples/code-review.sh ~/myproject "*.py"
./examples/code-review.sh ~/myproject "*.go"
```

Output → `~/code-review/YYYYMMDD_HHMMSS/`
- `review_FILENAME.md` — per-file annotated review
- `review.md` — consolidated report with risk register

---

### `iterative-coder.sh`
Write, run, fix loop. APEX generates a Python solution, executes it, reads the error output, and rewrites until all tests pass or the iteration limit is reached. Deterministic exit: PASS or FAIL with a full report.

```bash
./examples/iterative-coder.sh "write a script that finds prime numbers up to N" 8
./examples/iterative-coder.sh "parse a CSV and compute per-column statistics" 6
```

Output → `~/coder/YYYYMMDD_HHMMSS/`
- `solution.py` — final passing script
- `run.log` — last execution output
- `report.md` — iterations required, final verdict

---

### `research-agent.sh`
Autonomous goal-driven research agent. Self-directs across a `SEARCH / THINK / DONE` loop, pulling from public APIs (HackerNews, Reddit), reasoning over accumulated knowledge, and producing a final Markdown report. Pass `"free"` to let the agent choose its own topic.

```bash
./examples/research-agent.sh "explain how transformer attention mechanisms work" 15
./examples/research-agent.sh "free"
```

Output → `~/agent/YYYYMMDD_HHMMSS/`
- `state.txt` — full accumulated knowledge trace
- `report.md` — final synthesised report

---

## Swarms

Multi-agent parallel orchestration. A coordinator decomposes a goal into N sub-goals, spawns parallel agent instances, collects their reports, and synthesises a unified output.

---

### `competitive-intelligence-swarm.sh`
Parallel competitive intelligence swarm. Decomposes a target company or product into N research dimensions — positioning, pricing, product, sentiment, hiring signals, tech stack — and synthesises findings into a structured strategic brief.

```bash
./examples/competitive-intelligence-swarm.sh "Vercel" 5 6
./examples/competitive-intelligence-swarm.sh "Linear" 4 5
```

Output → `~/competitive-intel/YYYYMMDD_HHMMSS/`
- `dimensions.txt` — research dimensions generated
- `agent_N/report.md` — per-dimension findings
- `brief.md` — full strategic intelligence brief

---

### `parallel-swarm.sh`
General-purpose parallel research swarm. Decomposes any topic into N orthogonal dimensions, runs agents concurrently, and synthesises findings into a unified report. The foundational swarm primitive — use this when no domain-specific swarm fits the task.

```bash
./examples/parallel-swarm.sh "the current state of fusion energy" 5 8
./examples/parallel-swarm.sh "supply chain vulnerabilities in semiconductor manufacturing" 4 6
# args: "topic" [agents] [iterations_per_agent]
```

Output → `~/swarm/YYYYMMDD_HHMMSS/`
- `dimensions.txt` — decomposed research dimensions
- `agent_N/report.md` — per-agent findings
- `combined.txt` — raw report aggregation
- `report.md` — synthesised final report

---

### `recursive-self-improvement-swarm.sh`
APEX rewrites itself. Five sequential agents per generation: an architect critiques the codebase, an engineer proposes changes, an implementer applies them, a QA agent issues a `PASS / WARN / FAIL` verdict, and a technical writer documents what changed. The improved source becomes input to the next generation. Halts on regression, convergence, or max generations.

```bash
./examples/recursive-self-improvement-swarm.sh 5 ~/code/apps/axiom-apex
./examples/recursive-self-improvement-swarm.sh 3   # defaults to current apex root
```

Output → `~/swarm/rsi/YYYYMMDD_HHMMSS/`
- `gen_N/src/` — full apex source after generation N
- `gen_N/critique.md` — architectural critique
- `gen_N/proposal.md` — concrete change proposals
- `gen_N/impl_summary.txt` — changes actually implemented
- `gen_N/test_report.md` — QA verdict and regression findings
- `gen_N/changelog.md` — per-generation diff and changelog
- `generation_log.md` — full run history across all generations

---

*Built with [APEX](https://github.com/axiom-llc/axiom-apex) · [Axiom LLC](https://axiom-llc.github.io)*
