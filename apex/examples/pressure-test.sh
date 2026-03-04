#!/usr/bin/env bash
# pressure-test.sh — Dialectic swarm for hardening any thesis
# Each generation: steelman → antithesis → synthesis → stress-test
# The synthesis becomes the new thesis. Runs until convergence or max generations.
#
# Usage: ./pressure-test.sh "thesis" [generations]
#        ./pressure-test.sh "$(cat design-doc.md)" [generations]
# Example: ./pressure-test.sh "microservices are the right architecture for this system" 4

set -euo pipefail

THESIS="${1:-}"
MAX_GEN="${2:-4}"
APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

if [[ -z "$THESIS" ]]; then
    echo "Usage: $0 \"thesis\" [generations]"
    exit 1
fi

OUTDIR="$HOME/swarm/pressure-test/$(date +%Y%m%d_%H%M%S)"
JOURNAL="$OUTDIR/journal.md"
mkdir -p "$OUTDIR"
cd "$APEX_ROOT"

echo "▶ Thesis      : ${THESIS:0:80}..."
echo "▶ Generations : $MAX_GEN"
echo "▶ Output      : $OUTDIR"
echo ""

cat > "$JOURNAL" << EOF
# Pressure Test — $(date)
**Original thesis:** $THESIS

---

EOF

# Seed
CURRENT_THESIS="$OUTDIR/thesis_0.txt"
echo "$THESIS" > "$CURRENT_THESIS"

# ── Main loop ──────────────────────────────────────────────────────────────────
for GEN in $(seq 1 "$MAX_GEN"); do
    GENDIR="$OUTDIR/gen_${GEN}"
    mkdir -p "$GENDIR"

    PREV_THESIS="$OUTDIR/thesis_$((GEN-1)).txt"
    STEELMAN="$GENDIR/steelman.md"
    ANTITHESIS="$GENDIR/antithesis.md"
    SYNTHESIS="$GENDIR/synthesis.md"
    SURVIVORS="$GENDIR/survivors.md"
    NEXT_THESIS="$OUTDIR/thesis_${GEN}.txt"
    VERDICT="$GENDIR/verdict.txt"

    echo "══════════════════════════════════════════"
    echo "  GENERATION ${GEN} / ${MAX_GEN}"
    echo "══════════════════════════════════════════"
    echo ""

    # ── Agent 1 & 2 in parallel: Steelman + Antithesis ────────────────────────
    echo "── [Agents 1 & 2] Steelmanning and generating antithesis in parallel..."

    (
        apex "You are a steelman agent. Your job is to make the given thesis as strong as possible.

Read the current thesis from ${PREV_THESIS} using read_file.

Rewrite it as the strongest possible version of itself:
- Make every assumption explicit and justified
- Pre-address the most obvious objections inline
- Back every claim with reasoning or evidence
- Fill gaps in the argument
- Do not add new positions — only strengthen what is already there

Output the steelmanned thesis only. No commentary, no preamble.
Write to ${STEELMAN} using write_file"
    ) &
    PID_STEEL=$!

    (
        apex "You are an antithesis agent. Your job is to construct the strongest possible opposing position.

Read the current thesis from ${PREV_THESIS} using read_file.

Write a fully-formed opposing thesis of equal rigour:
- Do not critique the original — construct an independent counter-position
- Make it as internally coherent and well-reasoned as the original
- Attack the foundations, not the surface
- This is not a rebuttal — it is an alternative thesis that, if correct, makes the original wrong

Output the antithesis only. No commentary, no preamble.
Write to ${ANTITHESIS} using write_file"
    ) &
    PID_ANTI=$!

    wait $PID_STEEL && echo "   ✓ steelman" || echo "   ⚠ steelman failed"
    wait $PID_ANTI  && echo "   ✓ antithesis" || echo "   ⚠ antithesis failed"

    # ── Agent 3: Synthesis ─────────────────────────────────────────────────────
    echo ""
    echo "── [Agent 3] Synthesising..."

    apex "You are a synthesis agent. You have a steelmanned thesis and a strong antithesis. Forge a new position.

Read the steelmanned thesis from ${STEELMAN} using read_file.
Read the antithesis from ${ANTITHESIS} using read_file.

Produce a synthesis that:
- Inherits every element from the steelman that survived contact with the antithesis
- Inherits every element from the antithesis that the steelman could not defeat
- Discards everything that was genuinely refuted by the other side
- Resolves contradictions with a coherent higher-order position — not a compromise
- Is a genuinely new, stronger position — not a softened average of the two

The synthesis must take a clear position. No hedging, no 'it depends', no 'on one hand'.
Output the synthesis only. No commentary, no preamble.
Write to ${SYNTHESIS} using write_file"

    if [[ ! -f "$SYNTHESIS" ]]; then
        echo "✗ Agent 3 failed — aborting"
        break
    fi
    echo "   ✓ synthesis written"

    # ── Agent 4: Stress-test ───────────────────────────────────────────────────
    echo ""
    echo "── [Agent 4] Stress-testing synthesis for inherited assumptions..."

    apex "You are a stress-test agent. A synthesis has been produced from two opposing positions.
Your job is to find what survived that shouldn't have.

Read the synthesis from ${SYNTHESIS} using read_file.
Read the steelmanned thesis from ${STEELMAN} using read_file.
Read the antithesis from ${ANTITHESIS} using read_file.

Identify every assumption in the synthesis that was:
- Inherited uncritically from the steelman without being tested against the antithesis
- Inherited uncritically from the antithesis without being tested against the steelman
- Present in both and therefore never challenged by either

For each survivor:
- State the assumption
- State why it was never challenged
- State what would happen to the synthesis if the assumption is false

If no unchallenged assumptions remain, say so explicitly.
Write to ${SURVIVORS} using write_file"

    echo "   ✓ stress-test complete"

    # ── Judge: check for convergence ───────────────────────────────────────────
    echo ""
    echo "── [Judge] Evaluating convergence..."

    apex "You are evaluating whether a dialectic process has converged.

Read the original thesis from ${PREV_THESIS} using read_file.
Read the new synthesis from ${SYNTHESIS} using read_file.
Read the unchallenged assumptions report from ${SURVIVORS} using read_file.

Determine the status:
- CONVERGED: the synthesis and the original thesis are making the same core claims,
  OR the survivors report says no unchallenged assumptions remain and the synthesis is stable.
- EVOLVING: meaningful differences remain, further pressure will produce a stronger position.
- DEADLOCK: the synthesis is not coherent — the thesis and antithesis are genuinely irreconcilable.

Write to ${VERDICT} using write_file in this exact format:
STATUS: [CONVERGED|EVOLVING|DEADLOCK]
REASON: one sentence
DELTA: one sentence describing how much the position shifted this generation"

    # Copy synthesis forward as next thesis
    cp "$SYNTHESIS" "$NEXT_THESIS"

    STATUS=$(grep "^STATUS:" "$VERDICT" 2>/dev/null | cut -d' ' -f2 || echo "EVOLVING")
    REASON=$(grep "^REASON:" "$VERDICT" 2>/dev/null | cut -d':' -f2- | xargs || echo "")
    DELTA=$(grep "^DELTA:" "$VERDICT" 2>/dev/null | cut -d':' -f2- | xargs || echo "")

    echo "   Status : $STATUS"
    echo "   Reason : $REASON"
    echo "   Delta  : $DELTA"

    # Append generation to journal
    cat >> "$JOURNAL" << EOF
## Generation ${GEN} — ${STATUS}
**Delta:** ${DELTA}

### Synthesis
$(cat "$SYNTHESIS")

### Unchallenged Assumptions
$(cat "$SURVIVORS")

---

EOF

    if [[ "$STATUS" == "CONVERGED" ]]; then
        echo ""
        echo "✓ CONVERGED at generation ${GEN} — position is stable"
        break
    fi

    if [[ "$STATUS" == "DEADLOCK" ]]; then
        echo ""
        echo "✗ DEADLOCK at generation ${GEN} — positions are irreconcilable"
        echo "  This is itself a meaningful result. See journal for full trace."
        break
    fi

    echo ""
    echo "✓ Generation ${GEN} complete — continuing..."
    echo ""
done

# ── Final report ───────────────────────────────────────────────────────────────
FINAL="$OUTDIR/final.md"
LAST_THESIS=$(ls "$OUTDIR"/thesis_*.txt | sort -t_ -k2 -n | tail -1)

apex "You are writing the final report of a dialectic pressure-test.

Read the full journal at ${JOURNAL} using read_file.
Read the final position at ${LAST_THESIS} using read_file.

Write a concise final report in Markdown:
1. **Original Thesis** — restate it in one sentence
2. **Final Position** — the hardened result, stated clearly and completely
3. **What Changed** — the most significant shifts from original to final, bullet list
4. **Residual Risks** — unchallenged assumptions that remain, if any
5. **Verdict** — one sentence: is this position pressure-tested and trustworthy, or not?

Write to ${FINAL} using write_file"

echo ""
echo "══════════════════════════════════════════"
echo "  PRESSURE TEST COMPLETE"
echo "══════════════════════════════════════════"
echo ""
cat "$FINAL" 2>/dev/null
echo ""
echo "  Journal     : $JOURNAL"
echo "  Final report: $FINAL"
echo "  Generations : $OUTDIR/gen_*/"
