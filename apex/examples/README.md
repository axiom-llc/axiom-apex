# Examples

Runnable demonstrations of [APEX](https://github.com/axiom-llc/apex) capabilities.
Each script is a self-contained agent or swarm — no additional frameworks required.

## Prerequisites

```bash
export GEMINI_API_KEY=your-key
pip install -e .
```

Optional, unlocks specific examples:
```bash
sudo pacman -S espeak-ng   # spoken output (Arch)
sudo pacman -S openscad    # generative-3d.sh
```

---

## Agents

Single-agent loops with autonomous decision-making.

### `research-agent.sh`
Autonomous goal-driven research agent. Operates on a self-directed `SEARCH / THINK / DONE`
loop, pulling from public APIs (HackerNews, Reddit), reasoning over accumulated knowledge,
and producing a final Markdown report. Pass `"free"` to let the agent choose its own topic.

```bash
./examples/research-agent.sh "explain how transformer attention mechanisms work" 15
./examples/research-agent.sh "free"
```

Output → `~/agent/YYYYMMDD_HHMMSS/`
- `state.txt` — full accumulated knowledge trace
- `report.md` — final synthesised report

---

### `chargen.sh`
Iterative character profile generator. Cycles through background, personality, and skills
dimensions across N passes, accumulating state and synthesising a final Markdown character
sheet. Demonstrates structured state accumulation and iterative LLM refinement.

```bash
./examples/chargen.sh "disgraced intelligence analyst turned whistleblower" 6
./examples/chargen.sh   # uses default concept
```

Output → `~/chargen/YYYYMMDD_HHMMSS/`
- `iter_N.txt` — per-iteration dimension expansions
- `profile.txt` — full accumulated profile
- `character_sheet.md` — final synthesised output

---

### `generative-3d.sh`
Iterative AI-driven 3D model generator. Generates an OpenSCAD parametric enclosure,
compiles to STL, feeds compile output and errors back to the agent for refinement.
Demonstrates a compile-test-fix convergence loop with no human intervention.
Requires `openscad` (headless).

```bash
./examples/generative-3d.sh 5   # 5 refinement iterations
```

Output → `~/generative-3d/YYYYMMDD_HHMMSS/`
- `enclosure_iter_N.stl` — per-iteration STL history
- `enclosure_final.stl` — final compiled model
- `enclosure.scad` — final OpenSCAD source

---

### `code-review.sh`
Multi-pass code review agent. Analyses a codebase across three sequential layers —
correctness, security, and quality — producing per-file annotations and a consolidated
review report with severity-ranked findings and a refactor roadmap.

```bash
./examples/code-review.sh ~/myproject "*.py"
./examples/code-review.sh ~/myproject "*.go"
```

Output → `~/code-review/YYYYMMDD_HHMMSS/`
- `review_FILENAME.md` — per-file annotated review
- `review.md` — consolidated report with risk register

---

### `changelog-writer.sh`
Git-aware changelog and release notes generator. Reads the commit log, classifies
commits by type, infers the correct SemVer bump, and produces both a `CHANGELOG.md`
entry and polished release notes. Accepts any ref range.

```bash
./examples/changelog-writer.sh ~/myproject v1.2.0
./examples/changelog-writer.sh ~/myproject HEAD~30
```

Output → `~/changelog/YYYYMMDD_HHMMSS/`
- `classified.json` — typed commit classification
- `CHANGELOG.md` — Keep a Changelog format entry
- `RELEASE_NOTES.md` — audience-facing release notes

---

### `postmortem.sh`
Blameless incident post-mortem generator. Ingests logs, a timeline, and symptom notes
from an incident directory, reconstructs a chronological timeline, runs 5-whys root
cause analysis, and produces a structured post-mortem document with prioritised action items.

```bash
mkdir -p ~/incidents/my-incident/logs
echo "API returned 503 from 14:00 UTC" > ~/incidents/my-incident/symptoms.txt
echo "13:55 Deployed v1.3.1 to production" > ~/incidents/my-incident/timeline.txt
./examples/postmortem.sh ~/incidents/my-incident
```

Output → `~/postmortem/YYYYMMDD_HHMMSS/`
- `evidence.txt` — aggregated ingested evidence
- `timeline_reconstructed.txt` — chronological event table
- `analysis.txt` — 5-whys RCA and root cause classification
- `postmortem.md` — full blameless post-mortem document

---

### `debate-engine.sh`
Two-agent adversarial debate with judge scoring. Agent A argues FOR, Agent B argues
AGAINST, across N rounds with a stateless judge scoring each round on logical strength,
rebuttal quality, and rhetorical effectiveness. Produces a full transcript and final verdict.

```bash
./examples/debate-engine.sh "AI will eliminate more jobs than it creates" 4
./examples/debate-engine.sh "open source AI models are net beneficial to society" 3
```

Output → `~/debate/YYYYMMDD_HHMMSS/`
- `transcript.md` — full round-by-round debate transcript
- `verdict.md` — judge's final verdict with analysis

---

### `pressure-test.sh`
Dialectic swarm for hardening any thesis — an architectural decision, product strategy,
technical approach, or argument. Each generation: steelman and antithesis run in parallel,
a synthesis agent merges the strongest elements of each, a stress-test agent flags
assumptions that survived unchallenged. The synthesis becomes the new thesis. Terminates
on convergence, deadlock, or max generations. Produces a final hardened position with
residual risk register.

```bash
./examples/pressure-test.sh "microservices are the right architecture for this system" 4
./examples/pressure-test.sh "$(cat design-doc.md)" 5
./examples/pressure-test.sh "we should rewrite apex in Go" 3
```

Output → `~/swarm/pressure-test/YYYYMMDD_HHMMSS/`
- `gen_N/steelman.md` — steelmanned thesis per generation
- `gen_N/antithesis.md` — opposing thesis per generation
- `gen_N/synthesis.md` — merged position per generation
- `gen_N/survivors.md` — unchallenged assumptions per generation
- `journal.md` — full generation-by-generation trace
- `final.md` — hardened final position with risk register

---

## Swarms

Multi-agent parallel orchestration. A coordinator decomposes a goal into N sub-goals,
spawns parallel agent instances, collects their reports, and synthesises a unified output.

### `research-swarm.sh`
Parallel research swarm. Decomposes a topic into N orthogonal research angles, runs
parallel `research-agent.sh` instances, and synthesises findings into a unified report.
Pass `"free"` to let the swarm choose its own topic.

```bash
./examples/research-swarm.sh "quantum computing" 4 8
./examples/research-swarm.sh "free"
# args: "topic" [agents] [iterations_per_agent]
```

Output → `~/swarm/YYYYMMDD_HHMMSS/`
- `subgoals.txt` — decomposed research angles
- `agent_N/report.md` — per-agent reports
- `combined.txt` — raw report aggregation
- `report.md` — synthesised final report

---

### `competitive-intelligence-swarm.sh`
Parallel competitive intelligence swarm. Decomposes a target company or product into
N research dimensions — positioning, pricing, product, sentiment, hiring signals,
tech stack — and synthesises findings into a structured strategic brief.

```bash
./examples/competitive-intelligence-swarm.sh "Vercel" 5 6
./examples/competitive-intelligence-swarm.sh "Linear" 4 5
```

Output → `~/competitive-intel/YYYYMMDD_HHMMSS/`
- `dimensions.txt` — research dimensions generated
- `agent_N/report.md` — per-dimension findings
- `brief.md` — full strategic intelligence brief

---

### `threat-model-swarm.sh`
Parallel STRIDE-aligned threat modelling swarm. Decomposes a system into N attack
surfaces, runs parallel agents to enumerate threats per surface, and synthesises a
full threat model with DREAD scoring and a prioritised mitigation roadmap.

```bash
./examples/threat-model-swarm.sh "REST API with JWT auth, PostgreSQL, Redis, AWS ECS" 6 5
./examples/threat-model-swarm.sh "mobile app with BLE pairing and cloud sync" 5 5
```

Output → `~/threat-model/YYYYMMDD_HHMMSS/`
- `attack_surfaces.txt` — decomposed attack surfaces
- `agent_N/report.md` — per-surface threat analysis
- `threat_model.md` — full STRIDE/DREAD threat model
- `mitigations.md` — prioritised mitigation roadmap

---

### `due-diligence-swarm.sh`
Parallel technical due diligence swarm. Builds a project manifest from a local
repository, decomposes assessment across N dimensions (architecture, security,
scalability, test coverage, dependency health, debt, ops readiness), and produces
an investor-grade technical report alongside a one-page executive summary.

```bash
./examples/due-diligence-swarm.sh ~/code/target-project 7 5
```

Output → `~/due-diligence/YYYYMMDD_HHMMSS/`
- `manifest.txt` — extracted project structure and metadata
- `agent_N/report.md` — per-dimension assessments
- `technical_dd.md` — full technical due diligence report
- `executive_summary.md` — one-page non-technical summary

---

### `worldbuilding-swarm.sh`
Parallel world construction engine. Generates founding axioms from a concept, spawns
agents across independent world dimensions (geography, history, factions, economics,
belief systems, technology, culture), enforces cross-domain consistency at synthesis,
and produces a complete world bible with a quick-reference card.

```bash
./examples/worldbuilding-swarm.sh "post-collapse solarpunk archipelago" 7 5
./examples/worldbuilding-swarm.sh "hard sci-fi generation ship that lost its destination" 6 6
./examples/worldbuilding-swarm.sh "dying empire at the edge of a technological singularity"
```

Output → `~/worldbuilding/YYYYMMDD_HHMMSS/`
- `world_seed.txt` — founding axioms and fixed truths
- `dimensions.txt` — world-building dimensions generated
- `agent_N/report.md` — per-dimension lore documents
- `world_bible.md` — full cross-referenced world bible
- `quick_reference.md` — writer/GM quick-reference card

---

### `revenue-hunt.sh`
Autonomous revenue opportunity identification and execution planning swarm. Feed it a
description of your skills, product, or market position. 10 agents across 5 phases
identify the highest-ROI opportunity, model its financials, analyse competition, select
a winner, and produce a complete execution package: day-by-day GTM plan, cold outreach
copy, landing page, pricing architecture, objection playbook, and risk register.

```bash
./examples/revenue-hunt.sh "Python automation and AI integration, 1 developer, B2B focus" bootstrap 60
./examples/revenue-hunt.sh "$(cat company-profile.md)" low 90
./examples/revenue-hunt.sh "no-code SaaS tools for small law firms" funded 120
# args: "description" [bootstrap|low|funded] [days_to_revenue]
```

Output → `~/swarm/revenue-hunt/YYYYMMDD_HHMMSS/`
- `opportunities.md` — 5 ranked revenue opportunities with financial ceilings
- `financial_models.md` — per-opportunity models: CAC, LTV, payback, ramen breakeven
- `competitive.md` — named competitors, pricing benchmarks, kill risks per opportunity
- `winner.md` — selected opportunity with scored rationale and investment thesis
- `gtm_plan.md` — day-by-day execution plan across the full time horizon
- `outreach.md` — 3 cold outreach variants: problem-led, proof-led, insight-led
- `landing_page.md` — full landing page copy: headline through FAQ
- `pricing.md` — 3-tier pricing architecture with expansion motion
- `objections.md` — 8-objection sales playbook and 5-risk register
- `EXECUTION_PLAN.md` — full compiled package, start here

---

### `recursive-self-improvement-swarm.sh`
Apex rewrites itself. 5 sequential agents per generation: an architect critiques the
codebase, an engineer proposes concrete changes, an implementer applies them, a QA agent
runs regression tests and issues a PASS / WARN / FAIL verdict, and a technical writer
diffs and documents what changed. The improved source becomes the input to the next
generation. Halts on regression, convergence (no meaningful critique), or max generations.
Final evolved source is diffable and copyable back to the live codebase.

```bash
./examples/recursive-self-improvement-swarm.sh 5 ~/code/apps/apex-cli
./examples/recursive-self-improvement-swarm.sh 3   # defaults to current apex root
# args: [max_generations] [apex_src_path]
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

## Architecture Notes

All swarms follow the same pattern and are composable:

```
coordinator (apex)
  └── generates N sub-goals
        └── parallel bash subshells
              └── research-agent.sh (per sub-goal)
                    └── SEARCH / THINK / DONE loop
                          └── public APIs (HN, Reddit)
        └── wait for all PIDs
  └── synthesis pass (apex)
        └── final report
```

Single agents use the same `SEARCH / THINK / DONE` loop in isolation.
All scripts are self-contained, require only `apex` and `GEMINI_API_KEY`,
and write timestamped output directories — safe to run multiple times concurrently.

---

*Built with [APEX](https://github.com/axiom-llc/apex) by [Axiom LLC](https://github.com/axiom-llc)*
