#!/usr/bin/env bash
# parallel-swarm.sh — N-agent parallel research swarm
# Decomposes any topic into orthogonal dimensions, runs agents in parallel,
# synthesises findings into a structured report.
# Usage: ./parallel-swarm.sh "topic" [agents] [iterations_per_agent]
# Example: ./parallel-swarm.sh "the current state of fusion energy" 5 8

set -euo pipefail

TOPIC="${1:-}"
AGENTS="${2:-5}"
ITER="${3:-8}"

[[ -z "$TOPIC" ]] && echo "Usage: $0 \"topic\" [agents] [iterations]" && exit 1

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_SCRIPT="$(dirname "$0")/research-agent.sh"
OUTDIR="$HOME/swarm/$(date +%Y%m%d_%H%M%S)"
DIMENSIONS="$OUTDIR/dimensions.txt"
COMBINED="$OUTDIR/combined.txt"
REPORT="$OUTDIR/report.md"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Topic   : $TOPIC"
echo "▶ Agents  : $AGENTS"
echo "▶ Iter    : $ITER"
echo "▶ Output  : $OUTDIR"
echo ""

# ── Decompose topic into research dimensions ──────────────
echo "── Decomposing topic..."

apex "You are a research director decomposing a topic for a parallel research swarm.

Topic: ${TOPIC}

Generate exactly ${AGENTS} orthogonal research dimensions.
Each dimension must be independently researchable.
Collectively they must give complete coverage of the topic.
Each dimension should be a specific, concrete research question.

Output exactly ${AGENTS} lines. One dimension per line. No numbering, no bullets.
Write to ${DIMENSIONS} using write_file"

[[ ! -f "$DIMENSIONS" ]] && echo "✗ Decomposition failed" && exit 1

echo "── Dimensions:"
cat -n "$DIMENSIONS"
echo ""

# ── Launch parallel agents ────────────────────────────────
echo "── Launching ${AGENTS} agents..."

PIDS=()
i=0
while IFS= read -r dimension; do
    [[ -z "$dimension" ]] && continue
    AGENT_OUT="$OUTDIR/agent_${i}"
    mkdir -p "$AGENT_OUT"
    (
        export OUTDIR_OVERRIDE="$AGENT_OUT"
        bash "$AGENT_SCRIPT" "$dimension" "$ITER" 2>&1 | sed "s/^/  [agent_${i}] /"
    ) &
    PIDS+=($!)
    echo "   agent_${i} (pid ${PIDS[-1]}): $dimension"
    i=$((i+1))
done < "$DIMENSIONS"

echo ""
echo "── Waiting for ${#PIDS[@]} agents..."
for pid in "${PIDS[@]}"; do
    wait "$pid" && echo "   ✓ pid $pid" || echo "   ⚠ pid $pid exited non-zero"
done

# ── Collect reports ───────────────────────────────────────
echo ""
echo "── Collecting reports..."
> "$COMBINED"

for j in $(seq 0 $((AGENTS-1))); do
    AGENT_REPORT=$(find "$OUTDIR/agent_${j}" -name "report.md" 2>/dev/null | head -1)
    if [[ -f "$AGENT_REPORT" ]]; then
        echo "=== DIMENSION ${j} ===" >> "$COMBINED"
        cat "$AGENT_REPORT" >> "$COMBINED"
        echo "" >> "$COMBINED"
        echo "   ✓ agent_${j}"
    else
        echo "   ⚠ agent_${j} — no report"
    fi
done

# ── Synthesis ─────────────────────────────────────────────
echo ""
echo "── Synthesising..."

apex "You are a senior analyst synthesising parallel research into a unified report.

Topic: ${TOPIC}

Read the combined agent findings using read_file from ${COMBINED}

Write a comprehensive Markdown report structured around the topic — choose headers
that fit the content, not a fixed template. Requirements:
- Integrate findings across dimensions — surface cross-cutting patterns
- Resolve contradictions between agents (prefer the more specific claim)
- Concrete throughout: names, numbers, dates, mechanisms
- No meta-commentary about the research process
- End with: Key Findings (5 bullets) and Open Questions (3 bullets)

Write to ${REPORT} using write_file"

echo ""
echo "✓ Swarm complete"
echo "  Dimensions : $DIMENSIONS"
echo "  Agents     : $OUTDIR/agent_*"
echo "  Report     : $REPORT"
