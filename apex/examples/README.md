# Examples

Runnable demonstrations of [APEX](https://github.com/axiom-llc/apex-cli) capabilities.
Each script is self-contained — no additional frameworks required beyond `apex` and `GEMINI_API_KEY`.

## Prerequisites

```bash
export GEMINI_API_KEY=your-key
```

Optional, required by specific examples:
```bash
sudo pacman -S espeak-ng   # spoken audio output (Arch)
sudo pacman -S openscad    # generative-3d.sh
```

---

## Agents

Single-agent loops with autonomous decision-making and iterative refinement.

---

### `changelog-writer.sh`
Git-aware changelog and release notes generator. Reads the commit log, classifies commits by type, infers the correct SemVer bump, and produces a `CHANGELOG.md` entry and polished release notes for any ref range.

```bash
./examples/changelog-writer.sh ~/myproject v1.2.0
./examples/changelog-writer.sh ~/myproject HEAD~30
```

Output → `~/changelog/YYYYMMDD_HHMMSS/`
- `classified.json` — typed commit classification
- `CHANGELOG.md` — Keep a Changelog format entry
- `RELEASE_NOTES.md` — audience-facing release notes

---

### `chargen.sh`
Iterative character profile generator. Cycles through background, personality, and skills dimensions across N passes, accumulating state and synthesising a final Markdown character sheet.

```bash
./examples/chargen.sh "disgraced intelligence analyst turned whistleblower" 6
./examples/chargen.sh   # uses default concept
```

Output → `~/chargen/YYYYMMDD_HHMMSS/`
- `iter_N.txt` — per-iteration dimension expansions
- `profile.txt` — full accumulated profile
- `character_sheet.md` — final synthesised output

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

### `debate-engine.sh`
Two-agent adversarial debate with judge scoring. Agent A argues FOR, Agent B argues AGAINST, across N rounds. A stateless judge scores each round on logical strength, rebuttal quality, and rhetorical effectiveness. Produces a full transcript and final verdict.

```bash
./examples/debate-engine.sh "AI will eliminate more jobs than it creates" 4
./examples/debate-engine.sh "open source AI models are net beneficial to society" 3
```

Output → `~/debate/YYYYMMDD_HHMMSS/`
- `transcript.md` — full round-by-round debate transcript
- `verdict.md` — judge's final verdict with analysis

---

### `generative-3d.sh`
AI-driven OpenSCAD model generator. Describe any object — interactively at the prompt or as a CLI argument — and the agent generates a parametric OpenSCAD model, compiles to STL, and feeds compile results back for iterative refinement. Requires `openscad`.

```bash
./examples/generative-3d.sh 5 "a parametric wall-mount cable organizer"
# or prompted:
./examples/generative-3d.sh 5
```

Output → `~/generative-3d/YYYYMMDD_HHMMSS/`
- `model_iter_N.stl` — per-iteration STL history
- `model_final.stl` — final compiled model
- `model.scad` — final OpenSCAD source

---

### `postmortem.sh`
Blameless incident post-mortem generator. Ingests logs, a timeline, and symptom notes from an incident directory, reconstructs a chronological timeline, runs 5-whys root cause analysis, and produces a structured post-mortem document with prioritised action items.

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

### `pressure-test.sh`
Dialectic swarm for hardening any thesis — an architectural decision, product strategy, technical approach, or argument. Steelman and antithesis run in parallel each generation; a synthesis agent merges the strongest elements; a stress-test agent flags unchallenged assumptions. Terminates on convergence, deadlock, or max generations.

```bash
./examples/pressure-test.sh "microservices are the right architecture for this system" 4
./examples/pressure-test.sh "$(cat design-doc.md)" 5
```

Output → `~/swarm/pressure-test/YYYYMMDD_HHMMSS/`
- `gen_N/steelman.md` — steelmanned thesis per generation
- `gen_N/antithesis.md` — opposing thesis per generation
- `gen_N/synthesis.md` — merged position per generation
- `gen_N/survivors.md` — unchallenged assumptions per generation
- `journal.md` — full generation-by-generation trace
- `final.md` — hardened final position with risk register

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

### `due-diligence-swarm.sh`
Parallel technical due diligence swarm. Builds a project manifest from a local repository, decomposes assessment across N dimensions (architecture, security, scalability, test coverage, dependency health, debt, ops readiness), and produces an investor-grade technical report alongside a one-page executive summary.

```bash
./examples/due-diligence-swarm.sh ~/code/target-project 7 5
```

Output → `~/due-diligence/YYYYMMDD_HHMMSS/`
- `manifest.txt` — extracted project structure and metadata
- `agent_N/report.md` — per-dimension assessments
- `technical_dd.md` — full technical due diligence report
- `executive_summary.md` — one-page non-technical summary

---

### `recursive-self-improvement-swarm.sh`
APEX rewrites itself. Five sequential agents per generation: an architect critiques the codebase, an engineer proposes changes, an implementer applies them, a QA agent issues a PASS / WARN / FAIL verdict, and a technical writer documents what changed. The improved source becomes input to the next generation. Halts on regression, convergence, or max generations.

```bash
./examples/recursive-self-improvement-swarm.sh 5 ~/code/apps/apex-cli
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

### `research-swarm.sh`
Parallel research swarm. Decomposes a topic into N orthogonal research angles, runs parallel `research-agent.sh` instances, and synthesises findings into a unified report. Pass `"free"` to let the swarm choose its own topic.

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

### `revenue-hunt.sh`
Autonomous revenue opportunity identification and execution planning swarm. Ten agents across five phases identify the highest-ROI opportunity, model its financials, analyse competition, select a winner, and produce a complete execution package.

```bash
./examples/revenue-hunt.sh "Python automation and AI integration, 1 developer, B2B focus" bootstrap 60
./examples/revenue-hunt.sh "$(cat company-profile.md)" low 90
# args: "description" [bootstrap|low|funded] [days_to_revenue]
```

Output → `~/swarm/revenue-hunt/YYYYMMDD_HHMMSS/`
- `opportunities.md` — ranked revenue opportunities with financial ceilings
- `financial_models.md` — CAC, LTV, payback, ramen breakeven per opportunity
- `competitive.md` — named competitors, pricing benchmarks, kill risks
- `winner.md` — selected opportunity with scored rationale
- `gtm_plan.md` — day-by-day execution plan
- `outreach.md` — 3 cold outreach variants
- `landing_page.md` — full landing page copy
- `pricing.md` — 3-tier pricing architecture
- `objections.md` — 8-objection sales playbook and risk register
- `EXECUTION_PLAN.md` — full compiled package, start here

---

### `threat-model-swarm.sh`
Parallel STRIDE-aligned threat modelling swarm. Decomposes a system into N attack surfaces, runs parallel agents to enumerate threats per surface, and synthesises a full threat model with DREAD scoring and a prioritised mitigation roadmap.

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

### `worldbuilding-swarm.sh`
Parallel world construction engine. Generates founding axioms from a concept, spawns agents across independent world dimensions (geography, history, factions, economics, belief systems, technology, culture), enforces cross-domain consistency at synthesis, and produces a complete world bible with a quick-reference card.

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

*Built with [APEX](https://github.com/axiom-llc/apex-cli) · [Axiom LLC](https://axiom-llc.github.io)*
