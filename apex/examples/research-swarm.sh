#!/usr/bin/env bash
# research-swarm.sh — Parallel research swarm with synthesis layer
# Parent generates N sub-goals, runs parallel research-agent.sh calls, synthesises.
# Usage: ./research-swarm.sh "goal" [agents] [iterations_per_agent]
# Example: ./research-swarm.sh "research quantum computing" 4 8
# Pass "free" or omit goal to let the swarm choose its own topic

set -euo pipefail

GOAL="${1:-free}"
AGENTS="${2:-4}"
ITER="${3:-8}"

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_SCRIPT="${AGENT_SCRIPT:-$(dirname "$0")/research-agent.sh}"
OUTDIR="$HOME/swarm/$(date +%Y%m%d_%H%M%S)"
GOALSFILE="$OUTDIR/subgoals.txt"
REPORT="$OUTDIR/report.md"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Agents     : $AGENTS"
echo "▶ Iter/agent : $ITER"
echo "▶ Output     : $OUTDIR"
echo ""

# ── Bootstrap: choose topic if freeform ──────────────────────────────────────
NORMALIZED=$(echo "$GOAL" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]' | tr -d ' ')
if [[ "$NORMALIZED" == "free" || "$NORMALIZED" == "freechoice" || -z "$NORMALIZED" ]]; then
    echo "── Choosing topic..."
    TOPICFILE="$OUTDIR/topic.txt"

    apex "You are the coordinator of an autonomous research swarm.
Choose a single compelling, substantive topic for the swarm to investigate.
It should be rich enough to decompose into ${AGENTS} distinct research angles.
One line only — the topic, stated clearly.
Write to ${TOPICFILE} using write_file"

    [[ ! -f "$TOPICFILE" ]] && echo "✗ Topic generation failed" && exit 1
    GOAL=$(cat "$TOPICFILE")
    echo "▶ Topic      : $GOAL"
    echo ""
fi

# ── Parent generates N sub-goals ─────────────────────────────────────────────
echo "── Generating ${AGENTS} sub-goals..."

apex "You are coordinating a research swarm on this topic: ${GOAL}

Decompose this into exactly ${AGENTS} distinct, non-overlapping research sub-goals.
Each should cover a different angle, aspect, or dimension of the topic.
Together they should give full coverage of the topic.

Output exactly ${AGENTS} lines, one sub-goal per line, no numbering, no bullets.
Write to ${GOALSFILE} using write_file"

[[ ! -f "$GOALSFILE" ]] && echo "✗ Sub-goal generation failed" && exit 1

echo "── Sub-goals:"
cat -n "$GOALSFILE"
echo ""

# ── Launch parallel agents ────────────────────────────────────────────────────
echo "── Launching ${AGENTS} agents in parallel..."

PIDS=()
i=0
while IFS= read -r subgoal; do
    [[ -z "$subgoal" ]] && continue
    AGENT_OUT="$OUTDIR/agent_${i}"
    mkdir -p "$AGENT_OUT"

    (
        export OUTDIR_OVERRIDE="$AGENT_OUT"
        bash "$AGENT_SCRIPT" "$subgoal" "$ITER" 2>&1 | \
            sed "s/^/  [agent_${i}] /"
    ) &

    PIDS+=($!)
    echo "   agent_${i} launched (pid ${PIDS[-1]}): $subgoal"
    i=$((i+1))
done < "$GOALSFILE"

echo ""
echo "── Waiting for ${#PIDS[@]} agents..."
for pid in "${PIDS[@]}"; do
    wait "$pid" && echo "   ✓ pid $pid done" || echo "   ⚠ pid $pid exited non-zero"
done

# ── Collect reports ───────────────────────────────────────────────────────────
echo ""
echo "── Collecting agent reports..."
COMBINED="$OUTDIR/combined.txt"
> "$COMBINED"

for j in $(seq 0 $((AGENTS-1))); do
    AGENT_REPORT=$(find "$OUTDIR/agent_${j}" -name "report.md" 2>/dev/null | head -1)
    if [[ -f "$AGENT_REPORT" ]]; then
        echo "=== AGENT ${j} ===" >> "$COMBINED"
        cat "$AGENT_REPORT" >> "$COMBINED"
        echo "" >> "$COMBINED"
        echo "   ✓ agent_${j} report collected"
    else
        echo "   ⚠ agent_${j} no report found"
    fi
done

# ── Synthesis ─────────────────────────────────────────────────────────────────
echo ""
echo "── Synthesising final report..."

apex "You are the coordinator of a research swarm. The swarm investigated: ${GOAL}

${AGENTS} parallel agents each researched a different angle.
Read their combined findings using read_file from ${COMBINED}

Synthesise everything into a single authoritative Markdown report.
Structure it logically for the content — use whatever sections make sense.
Start with a sharp executive summary, then cover the full topic with depth.

Rules:
- Resolve contradictions between agents — note where they diverge
- Integrate findings across agents — find connections they missed individually
- Concrete throughout: names, dates, numbers, mechanisms
- No meta-commentary about the swarm or research process

Write the final report to ${REPORT} using write_file"

echo ""
echo "✓ Swarm complete"
echo "  Sub-goals   : $GOALSFILE"
echo "  Agent dirs  : $OUTDIR/agent_*"
echo "  Combined    : $COMBINED"
echo "  Final report: $REPORT"
