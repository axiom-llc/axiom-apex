#!/usr/bin/env bash
# debate-engine.sh — Two-agent adversarial debate with judge scoring
# Agent A argues FOR, Agent B argues AGAINST, Judge scores each round
# Demonstrates: multi-agent turn structure, adversarial prompting, structured scoring
# Usage: ./debate-engine.sh "proposition" [rounds]
# Example: ./debate-engine.sh "AI will eliminate more jobs than it creates" 4

set -euo pipefail

PROPOSITION="${1:-"open source AI models are net beneficial to society"}"
ROUNDS="${2:-3}"

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="$HOME/debate/$(date +%Y%m%d_%H%M%S)"
TRANSCRIPT="$OUTDIR/transcript.md"
VERDICT="$OUTDIR/verdict.md"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

SCORE_A=0
SCORE_B=0

echo "▶ Proposition : $PROPOSITION"
echo "▶ Rounds      : $ROUNDS"
echo "▶ Output      : $OUTDIR"
echo ""
echo "  Agent A → FOR"
echo "  Agent B → AGAINST"
echo "  Judge   → Scores each round"
echo ""

# ── Init transcript ───────────────────────────────────────────────────────────
cat > "$TRANSCRIPT" <<EOF
# Debate: $PROPOSITION

**Agent A** argues: FOR
**Agent B** argues: AGAINST

---
EOF

# ── Opening statements ────────────────────────────────────────────────────────
echo "── Opening statements"

OPEN_A="$OUTDIR/open_a.txt"
OPEN_B="$OUTDIR/open_b.txt"

apex "You are Agent A in a formal structured debate.
Proposition: '${PROPOSITION}'
Your position: STRONGLY IN FAVOUR.

Deliver a sharp 150-word opening statement.
Lead with your single strongest argument.
Establish the framing that most favours your position.
No hedging. No acknowledgement of counterarguments yet.
Plain prose, no markdown.
Write to ${OPEN_A} using write_file"

apex "You are Agent B in a formal structured debate.
Proposition: '${PROPOSITION}'
Your position: STRONGLY AGAINST.

Deliver a sharp 150-word opening statement.
Lead with your single strongest argument.
Establish the framing that most favours your position.
No hedging. No acknowledgement of counterarguments yet.
Plain prose, no markdown.
Write to ${OPEN_B} using write_file"

{
    echo "## Opening Statements"
    echo ""
    echo "### Agent A (FOR)"
    [[ -f "$OPEN_A" ]] && cat "$OPEN_A" || echo "[no output]"
    echo ""
    echo "### Agent B (AGAINST)"
    [[ -f "$OPEN_B" ]] && cat "$OPEN_B" || echo "[no output]"
    echo ""
    echo "---"
    echo ""
} >> "$TRANSCRIPT"

echo "   ✓ openings written"
espeak-ng "Opening statements complete. Beginning ${ROUNDS} rounds." 2>/dev/null || true

# ── Debate rounds ─────────────────────────────────────────────────────────────
for i in $(seq 1 "$ROUNDS"); do
    echo ""
    echo "── Round $i / $ROUNDS"

    ARG_A="$OUTDIR/round_${i}_a.txt"
    ARG_B="$OUTDIR/round_${i}_b.txt"
    SCORE_FILE="$OUTDIR/round_${i}_score.txt"

    apex "You are Agent A. Proposition: '${PROPOSITION}'. You argue FOR.

Full debate transcript so far:
$(cat "$TRANSCRIPT")

Round $i of $ROUNDS. Deliver your argument (120–180 words):
- Advance a NEW line of reasoning not yet made
- Directly rebut the most damaging point Agent B has raised
- Anticipate and pre-empt Agent B's next likely attack
No markdown. Plain prose.
Write to ${ARG_A} using write_file"

    apex "You are Agent B. Proposition: '${PROPOSITION}'. You argue AGAINST.

Full debate transcript so far:
$(cat "$TRANSCRIPT")

Round $i of $ROUNDS. Deliver your argument (120–180 words):
- Advance a NEW line of reasoning not yet made
- Directly rebut the most damaging point Agent A has raised
- Anticipate and pre-empt Agent A's next likely attack
No markdown. Plain prose.
Write to ${ARG_B} using write_file"

    # ── Judge scores the round ─────────────────────────────────────────────────
    apex "You are an impartial debate judge. Proposition: '${PROPOSITION}'

Round $i arguments:
AGENT A (FOR):
$(cat "$ARG_A" 2>/dev/null || echo "[no output]")

AGENT B (AGAINST):
$(cat "$ARG_B" 2>/dev/null || echo "[no output]")

Score this round on three criteria (each 1–10):
1. Logical strength of argument
2. Quality of rebuttal
3. Rhetorical effectiveness

Output format — exactly this structure, no extra text:
WINNER: (A|B|DRAW)
SCORE_A: (3–30)
SCORE_B: (3–30)
REASONING: (2 sentences explaining the round outcome)

Write to ${SCORE_FILE} using write_file"

    # ── Parse scores ───────────────────────────────────────────────────────────
    if [[ -f "$SCORE_FILE" ]]; then
        R_A=$(grep "^SCORE_A:" "$SCORE_FILE" | awk '{print $2}' || echo 0)
        R_B=$(grep "^SCORE_B:" "$SCORE_FILE" | awk '{print $2}' || echo 0)
        WINNER=$(grep "^WINNER:" "$SCORE_FILE" | awk '{print $2}' || echo "DRAW")
        REASONING=$(grep "^REASONING:" "$SCORE_FILE" | cut -d: -f2- || echo "")

        SCORE_A=$((SCORE_A + R_A))
        SCORE_B=$((SCORE_B + R_B))

        echo "   Round winner : $WINNER  (A:$R_A  B:$R_B)"
        espeak-ng "Round $i winner: $WINNER" 2>/dev/null || true
    fi

    # ── Append to transcript ───────────────────────────────────────────────────
    {
        echo "## Round $i"
        echo ""
        echo "### Agent A"
        [[ -f "$ARG_A" ]] && cat "$ARG_A" || echo "[no output]"
        echo ""
        echo "### Agent B"
        [[ -f "$ARG_B" ]] && cat "$ARG_B" || echo "[no output]"
        echo ""
        echo "### Judge"
        [[ -f "$SCORE_FILE" ]] && cat "$SCORE_FILE" || echo "[no score]"
        echo ""
        echo "---"
        echo ""
    } >> "$TRANSCRIPT"
done

# ── Final verdict ─────────────────────────────────────────────────────────────
echo ""
echo "── Final verdict..."

if (( SCORE_A > SCORE_B )); then
    OVERALL_WINNER="Agent A (FOR)"
elif (( SCORE_B > SCORE_A )); then
    OVERALL_WINNER="Agent B (AGAINST)"
else
    OVERALL_WINNER="DRAW"
fi

apex "You are the chief judge of this debate. Proposition: '${PROPOSITION}'

Full transcript:
$(cat "$TRANSCRIPT")

Final scores — Agent A: ${SCORE_A} | Agent B: ${SCORE_B}
Declared winner by points: ${OVERALL_WINNER}

Write a final verdict as a Markdown document:
# Verdict: $PROPOSITION
## Result
(winner, final score, margin)
## Winning Arguments
(the 2–3 arguments that most decided the debate)
## Weakest Points
(one for each side — what they failed to adequately defend)
## Philosophical Note
(1 paragraph: what this debate reveals about the proposition's genuine complexity)

Write to ${VERDICT} using write_file"

echo ""
echo "✓ Debate complete"
echo "  Final score : A=$SCORE_A  B=$SCORE_B  Winner=$OVERALL_WINNER"
echo "  Transcript  : $TRANSCRIPT"
echo "  Verdict     : $VERDICT"

espeak-ng "Debate complete. Final winner: ${OVERALL_WINNER}. Scores: A ${SCORE_A}, B ${SCORE_B}." 2>/dev/null || true
