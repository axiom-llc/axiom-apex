# Examples
Runnable demonstrations of APEX capabilities.

## research-agent.sh
Autonomous goal-driven research agent. Self-directs across a SEARCH/THINK/DONE loop, pulling from public APIs (Wikipedia, HackerNews, Reddit), reasoning over accumulated knowledge, and producing a final Markdown report.
```bash
export GEMINI_API_KEY=your-key
./examples/research-agent.sh "explain how transformer attention mechanisms work" 15
./examples/research-agent.sh   # agent chooses its own topic
```
Output written to `~/agent/YYYYMMDD_HHMMSS/`:
- `state.txt` — full accumulated knowledge trace
- `report.md` — final synthesised report

## research-swarm.sh
Parallel swarm orchestration. A coordinator decomposes a topic into N sub-goals, spawns parallel `research-agent.sh` instances, collects their reports, and synthesises a unified final report.
```bash
export GEMINI_API_KEY=your-key
./examples/research-swarm.sh "quantum computing" 4 8
# args: "topic" [num_agents] [iterations_per_agent]
./examples/research-swarm.sh   # swarm chooses its own topic
```
Output written to `~/swarm/YYYYMMDD_HHMMSS/`:
- `subgoals.txt` — decomposed research angles
- `agent_N/report.md` — per-agent reports
- `combined.txt` — raw aggregation
- `report.md` — synthesised final report

## generative-3d.sh
Iterative AI-driven 3D model generator. Generates an OpenSCAD parametric model, compiles to STL, feeds compile results back to the agent for refinement. Demonstrates compile-test-fix convergence.
```bash
./examples/generative-3d.sh 5   # 5 refinement iterations
```
Requires: `openscad` (headless). Output written to `~/mechagen/YYYYMMDD_HHMMSS/`:
- `enclosure_iter_N.stl` — per-iteration STL history
- `enclosure_final.stl` — final compiled model
- `enclosure.scad` — final source

## chargen.sh
Iterative character profile generator. Cycles through background, personality, and skills dimensions across N passes, synthesising a final Markdown character sheet. Demonstrates structured state accumulation and iterative LLM refinement.
```bash
./examples/chargen.sh "disgraced intelligence analyst turned whistleblower" 6
./examples/chargen.sh   # uses default concept
```
Output written to `~/chargen/YYYYMMDD_HHMMSS/`:
- `iter_N.txt` — per-iteration expansions
- `profile.txt` — full accumulated profile
- `character_sheet.md` — final synthesised output

## Prerequisites
```bash
export GEMINI_API_KEY=your-key
pip install -r requirements.txt
```
