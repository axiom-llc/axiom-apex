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

| File | Contents |
|------|----------|
| `state.txt` | Full accumulated knowledge trace |
| `report.md` | Final synthesised report |

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

| File | Contents |
|------|----------|
| `iter_N.txt` | Per-iteration dimension expansions |
| `profile.txt` | Full accumulated profile |
| `character_sheet.md` | Final synthesised output |

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

| File | Contents |
|------|----------|
| `enclosure_iter_N.stl` | Per-iteration STL history |
| `enclosure_final.stl` | Final compiled model |
| `enclosure.scad` | Final OpenSCAD source |

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

| File | Contents |
|------|----------|
| `review_FILENAME.md` | Per-file annotated review |
| `review.md` | Consolidated report with risk register |

---

### `changelog-writer.sh`
Git-aware changelog and release notes generator. Reads the commit log, classifies
commits by type, infers the correct semver bump, and produces both a `CHANGELOG.md`
entry and polished release notes. Accepts any ref range.

```bash
./examples/changelog-writer.sh ~/myproject v1.2.0
./examples/changelog-writer.sh ~/myproject HEAD~30
```

Output → `~/changelog/YYYYMMDD_HHMMSS/`

| File | Contents |
|------|----------|
| `classified.json` | Typed commit classification |
| `CHANGELOG.md` | Keep a Changelog format entry |
| `RELEASE_NOTES.md` | Audience-facing release notes |

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

| File | Contents |
|------|----------|
| `evidence.txt` | Aggregated ingested evidence |
| `timeline_reconstructed.txt` | Chronological event table |
| `analysis.txt` | 5-whys RCA and root cause classification |
| `postmortem.md` | Full blameless post-mortem document |

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

| File | Contents |
|------|----------|
| `transcript.md` | Full round-by-round debate transcript |
| `verdict.md` | Judge's final verdict with analysis |

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
# args: "topic" [agents] [iterations_per_agent]
./examples/research-swarm.sh "free"
```

Output → `~/swarm/YYYYMMDD_HHMMSS/`

| File | Contents |
|------|----------|
| `subgoals.txt` | Decomposed research angles |
| `agent_N/report.md` | Per-agent reports |
| `combined.txt` | Raw report aggregation |
| `report.md` | Synthesised final report |

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

| File | Contents |
|------|----------|
| `dimensions.txt` | Research dimensions generated |
| `agent_N/report.md` | Per-dimension findings |
| `brief.md` | Full strategic intelligence brief |

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

| File | Contents |
|------|----------|
| `attack_surfaces.txt` | Decomposed attack surfaces |
| `agent_N/report.md` | Per-surface threat analysis |
| `threat_model.md` | Full STRIDE/DREAD threat model |
| `mitigations.md` | Prioritised mitigation roadmap |

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

| File | Contents |
|------|----------|
| `manifest.txt` | Extracted project structure and metadata |
| `agent_N/report.md` | Per-dimension assessments |
| `technical_dd.md` | Full technical due diligence report |
| `executive_summary.md` | One-page non-technical summary |

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

| File | Contents |
|------|----------|
| `world_seed.txt` | Founding axioms and fixed truths |
| `dimensions.txt` | World-building dimensions generated |
| `agent_N/report.md` | Per-dimension lore documents |
| `world_bible.md` | Full cross-referenced world bible |
| `quick_reference.md` | Writer/GM quick-reference card |

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
