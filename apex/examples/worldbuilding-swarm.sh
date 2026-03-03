#!/usr/bin/env bash
# worldbuilding-swarm.sh — Parallel AI-driven world construction engine
# Axiom LLC — https://github.com/axiom-llc/apex
#
# Spawns agents across independent world dimensions: geography, history, factions,
# economics, religion, technology, and culture. Each agent builds its domain
# with internal consistency enforced at synthesis. Final output: a coherent,
# cross-referenced world bible suitable for fiction, games, or interactive media.
#
# Demonstrates: creative multi-agent coordination, cross-domain consistency
# enforcement, iterative lore synthesis, structured world state management
#
# Usage: ./worldbuilding-swarm.sh "world concept" [agents] [iterations]
# Example: ./worldbuilding-swarm.sh "post-collapse solarpunk archipelago" 7 5
# Example: ./worldbuilding-swarm.sh "hard sci-fi generation ship that lost its destination" 6 6

set -euo pipefail

CONCEPT="${1:-"a dying empire at the edge of a technological singularity"}"
AGENTS="${2:-7}"
ITER="${3:-5}"

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_SCRIPT="${AGENT_SCRIPT:-$(dirname "$0")/research-agent.sh}"
OUTDIR="$HOME/worldbuilding/$(date +%Y%m%d_%H%M%S)"
WORLDSEED="$OUTDIR/world_seed.txt"
DIMENSIONSFILE="$OUTDIR/dimensions.txt"
BIBLE="$OUTDIR/world_bible.md"
QUICKREF="$OUTDIR/quick_reference.md"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Concept    : $CONCEPT"
echo "▶ Agents     : $AGENTS"
echo "▶ Iter/agent : $ITER"
echo "▶ Output     : $OUTDIR"
echo ""

espeak-ng "Beginning world construction for: $(echo "$CONCEPT" | cut -c1-60)" 2>/dev/null || true

# ── Generate world seed ───────────────────────────────────────────────────────
echo "── Generating world seed..."

apex "You are a master world-builder establishing the foundational axioms of a new world.

Core concept: ${CONCEPT}

Generate a world seed — the non-negotiable facts that all subsequent world-building
must be consistent with. This is the source of truth for all agents.

Include:
WORLD_NAME: (one evocative name)
SCALE: (planet / region / star system / other — and rough size)
ERA: (what kind of time period or technological level)
CORE_TENSION: (the central conflict or pressure that shapes everything)
PHYSICAL_LAWS: (any deviations from our reality — magic, FTL, psionics, etc.)
TONE: (the emotional register — grimdark / hopepunk / cosmic horror / etc.)
THREE_TRUTHS: (three facts about this world that are absolutely fixed)
THREE_UNKNOWNS: (three mysteries no one in this world has solved)

Be specific and generative — these axioms should spark the dimensions that follow.
Write as structured plain text (FIELD: value format).
Write to ${WORLDSEED} using write_file"

[[ ! -f "$WORLDSEED" ]] && echo "✗ World seed generation failed" && exit 1

echo "── World seed:"
cat "$WORLDSEED"
echo ""

WORLD_NAME=$(grep "^WORLD_NAME:" "$WORLDSEED" | cut -d: -f2 | xargs)

# ── Define world dimensions ───────────────────────────────────────────────────
echo "── Defining world dimensions..."

apex "You are a world-building coordinator. World seed:
$(cat "$WORLDSEED")

Core concept: ${CONCEPT}

Decompose this world into exactly ${AGENTS} dimensions for parallel development.
Each dimension should be independently buildable but deeply interconnected.

Draw from these world-building pillars (select and customise the most generative ${AGENTS}):
- Physical geography: terrain, climate, resources, natural hazards
- Deep history: founding events, turning points, lost civilisations, mythologised past
- Political factions: powers, alliances, conflicts, ideologies, key figures
- Economic systems: trade, scarcity, production, class structures, currencies
- Belief systems: religions, philosophies, cosmologies, rituals, heresies
- Technology & magic: what is possible, what is forbidden, how it shapes society
- Culture & daily life: language markers, art, food, social norms, taboos
- Underworld & shadows: criminal networks, secret societies, forbidden knowledge
- The frontier: unexplored territories, ancient ruins, dangerous borderlands

Output exactly ${AGENTS} lines. One dimension per line.
Each: a specific world-building goal seeded from the world axioms.
No numbering, no bullets.
Write to ${DIMENSIONSFILE} using write_file"

[[ ! -f "$DIMENSIONSFILE" ]] && echo "✗ Dimension generation failed" && exit 1

echo "── Dimensions:"
cat -n "$DIMENSIONSFILE"
echo ""

# ── Launch parallel agents ────────────────────────────────────────────────────
echo "── Launching ${AGENTS} world-building agents in parallel..."

PIDS=()
i=0
while IFS= read -r dimension; do
    [[ -z "$dimension" ]] && continue
    AGENT_OUT="$OUTDIR/agent_${i}"
    mkdir -p "$AGENT_OUT"
    cp "$WORLDSEED" "$AGENT_OUT/world_seed.txt"

    AUGMENTED_GOAL="You are a specialist world-builder constructing one dimension of a larger world.

WORLD SEED (non-negotiable axioms — all content must be consistent with these):
$(cat "$WORLDSEED")

YOUR DIMENSION: ${dimension}

Build this dimension with obsessive internal consistency and generative depth.
Requirements:
1. Everything must be consistent with the world seed axioms
2. Introduce 2–3 unexpected but internally logical elements
3. Create named specifics: people, places, organisations, artefacts, events
4. Build in narrative hooks — seeds of conflict, mystery, and story potential
5. Connect explicitly to at least two other likely world dimensions
6. Avoid clichés — subvert genre expectations where possible

Use HackerNews and Reddit to research real-world analogues, historical precedents,
or speculative ideas that could enrich this dimension with authenticity.

Produce a dense, specific lore document — not a list of facts, but a coherent
picture of how this dimension works and feels."

    (
        export OUTDIR_OVERRIDE="$AGENT_OUT"
        bash "$AGENT_SCRIPT" "$AUGMENTED_GOAL" "$ITER" 2>&1 | \
            sed "s/^/  [world_${i}] /"
    ) &

    PIDS+=($!)
    echo "   agent_${i} (pid ${PIDS[-1]}): ${dimension:0:60}..."
    i=$((i+1))
done < "$DIMENSIONSFILE"

echo ""
echo "── Waiting for ${#PIDS[@]} agents..."
for pid in "${PIDS[@]}"; do
    wait "$pid" && echo "   ✓ pid $pid" || echo "   ⚠ pid $pid exited non-zero"
done

# ── Collect dimension reports ─────────────────────────────────────────────────
echo ""
echo "── Collecting dimension reports..."
COMBINED="$OUTDIR/combined.txt"
> "$COMBINED"

for j in $(seq 0 $((AGENTS-1))); do
    AGENT_REPORT=$(find "$OUTDIR/agent_${j}" -name "report.md" 2>/dev/null | head -1)
    if [[ -f "$AGENT_REPORT" ]]; then
        echo "=== DIMENSION ${j} ===" >> "$COMBINED"
        cat "$AGENT_REPORT" >> "$COMBINED"
        echo "" >> "$COMBINED"
        echo "   ✓ agent_${j} collected"
    else
        echo "   ⚠ agent_${j} no report"
    fi
done

# ── World bible synthesis ─────────────────────────────────────────────────────
echo ""
echo "── Synthesising world bible..."

apex "You are the lead world-builder synthesising a complete world bible.
Concept: ${CONCEPT}
World name: ${WORLD_NAME:-"(see seed)"}

Read the world seed using read_file from ${WORLDSEED}
Read the combined dimension reports using read_file from ${COMBINED}

Produce a complete, cross-referenced world bible in Markdown.
Structure it around what was actually built — use organic section headers
that reflect this world's unique character, not a generic template.

Required elements:
1. World overview (2–3 paragraphs — the essential pitch for this world)
2. One section per major dimension, synthesised and deepened
3. Cross-references: where dimensions interact, depend on, or contradict each other
4. Contradiction resolution: where agents diverged, make a ruling and state it clearly
5. Named entities index: all named people, places, organisations in one reference section
6. Story hooks: 5–7 concrete, specific narrative entry points for a writer or game designer
7. Open questions: 3–5 deliberately unresolved mysteries that reward further development

Rules:
- Specific throughout — no 'a great city' when you can say 'Vetharis, the city built
  on the back of a dead colossus'
- Narrative voice: lore-bible style — present tense, declarative, authoritative
- Resolve contradictions decisively — note the ruling in a footnote
- Each section should feel lived-in, not designed

Write to ${BIBLE} using write_file"

# ── Quick reference card ──────────────────────────────────────────────────────
echo ""
echo "── Writing quick reference..."

apex "Read the world bible using read_file from ${BIBLE}

Produce a concise quick-reference card for a writer, GM, or creative collaborator
coming to this world for the first time:

# ${WORLD_NAME:-"World"} — Quick Reference

## The Pitch
(3 sentences — what this world is, what makes it distinctive, what stories it wants to tell)

## Core Tensions
(3 bullet points — the conflicts that drive everything)

## Five Things Everyone Knows
(common knowledge in this world — what its inhabitants take for granted)

## Five Things Nobody Knows
(mysteries, suppressed truths, or lost knowledge)

## Key Factions (3–5)
(name, one-sentence description, their goal, their method)

## Key Locations (3–5)
(name, one evocative sentence — what it is and what happens there)

## Tone & Feel
(3 reference points: 'feels like X meets Y in the vein of Z')

Write to ${QUICKREF} using write_file"

echo ""
echo "✓ World construction complete"
echo "  Concept    : $CONCEPT"
echo "  World      : ${WORLD_NAME:-"(see seed)"}"
echo "  Seed       : $WORLDSEED"
echo "  Dimensions : $OUTDIR/agent_*"
echo "  Bible      : $BIBLE"
echo "  Quick ref  : $QUICKREF"

espeak-ng "World construction complete. ${WORLD_NAME:-"World"} is ready." 2>/dev/null || true
