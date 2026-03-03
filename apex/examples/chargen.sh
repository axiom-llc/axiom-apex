#!/usr/bin/env bash
# chargen.sh — Iterative AI-driven character profile generator
# Cycles through character dimensions across N passes, synthesises final Markdown sheet
# Demonstrates: iterative LLM refinement, structured state accumulation
# Usage: ./chargen.sh "concept" [iterations]
# Example: ./chargen.sh "disgraced intelligence analyst turned whistleblower" 6

set -euo pipefail

CONCEPT="${1:-"a seasoned operative with divided loyalties"}"
ITERATIONS="${2:-6}"

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="$HOME/chargen/$(date +%Y%m%d_%H%M%S)"
PROFILE="$OUTDIR/profile.txt"
SHEET_MD="$OUTDIR/character_sheet.md"

DIMENSIONS=(
    "background and history: origin, formative events, turning points, secrets"
    "personality and psychology: traits, fears, desires, flaws, internal conflict"
    "skills and abilities: what they excel at, hard-won expertise, critical gaps"
)

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

cat > "$PROFILE" <<EOF
CHARACTER CONCEPT: $CONCEPT
---
EOF

echo "▶ Concept    : $CONCEPT"
echo "▶ Iterations : $ITERATIONS"
echo "▶ Output dir : $OUTDIR"
echo ""

# ── Iterative expansion ───────────────────────────────────────────────────────
for i in $(seq 1 "$ITERATIONS"); do

    DIM_INDEX=$(( (i - 1) % ${#DIMENSIONS[@]} ))
    DIMENSION="${DIMENSIONS[$DIM_INDEX]}"
    ITER_FILE="$OUTDIR/iter_${i}.txt"

    echo "── Iteration $i/$ITERATIONS : ${DIMENSION%%:*}"

    apex "Here is the character profile built so far:

$(cat "$PROFILE")

---
Your task: Expand and deepen the character's **${DIMENSION}**.

Rules:
- Stay strictly consistent with everything already established
- Add specific, concrete details — names, places, dates, events where relevant
- Introduce at least one unexpected but internally logical element per pass
- Do NOT restate or summarise existing content — only add or meaningfully refine
- Write in neutral lore-bible style (no second-person, no filler phrases)
- Length: 150–250 words for this section only

Write the result to ${ITER_FILE} using write_file"

    if [[ ! -f "$ITER_FILE" ]]; then
        echo "  ⚠ ${ITER_FILE} not written — skipping iteration"
        continue
    fi

    {
        echo ""
        echo "=== ITERATION $i: $(echo "${DIMENSION%%:*}" | tr '[:lower:]' '[:upper:]') ==="
        cat "$ITER_FILE"
    } >> "$PROFILE"

    echo "   ✓ iter_${i}.txt"
done

# ── Final synthesis ───────────────────────────────────────────────────────────
echo ""
echo "── Synthesising character sheet..."

apex "You have a complete iterative character development profile:

$(cat "$PROFILE")

Synthesise everything into a clean Markdown character sheet using exactly these sections:

# [Character Name]
## Concept
(1–2 sentence summary)
## Background
## Personality
## Skills & Abilities
## Secrets & Story Hooks
(2–3 concrete hooks usable directly in narrative or game contexts)

Rules:
- Resolve any contradictions — later iterations take precedence
- Each section: 3–6 tight sentences or a concise list; no padding
- Specific and concrete throughout — no vague placeholders
- Write as a lore document, not a description of the character

Write to ${SHEET_MD} using write_file"

echo ""
echo "✓ Done"
echo "  Raw profile : $PROFILE"
echo "  Sheet       : $SHEET_MD"
