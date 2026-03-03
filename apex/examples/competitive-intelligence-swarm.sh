#!/usr/bin/env bash
# competitive-intelligence-swarm.sh — Parallel competitive intelligence agent
# Axiom LLC — https://github.com/axiom-llc/apex
#
# Spawns N agents across orthogonal competitive dimensions:
# positioning, pricing, product, sentiment, hiring signals, technology stack.
# Synthesises findings into a structured strategic brief.
#
# Demonstrates: parallel market research, signal extraction, strategic synthesis
#
# Usage: ./competitive-intelligence-swarm.sh "company or product" [agents] [iterations]
# Example: ./competitive-intelligence-swarm.sh "Vercel" 5 6

set -euo pipefail

TARGET="${1:-}"
AGENTS="${2:-5}"
ITER="${3:-6}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 \"target company or product\" [agents] [iterations]"
    exit 1
fi

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_SCRIPT="${AGENT_SCRIPT:-$(dirname "$0")/research-agent.sh}"
OUTDIR="$HOME/competitive-intel/$(date +%Y%m%d_%H%M%S)"
GOALSFILE="$OUTDIR/dimensions.txt"
BRIEF="$OUTDIR/brief.md"
SUMMARY="$OUTDIR/summary.txt"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Target     : $TARGET"
echo "▶ Agents     : $AGENTS"
echo "▶ Iter/agent : $ITER"
echo "▶ Output     : $OUTDIR"
echo ""

espeak-ng "Starting competitive intelligence swarm on ${TARGET}" 2>/dev/null || true

# ── Generate research dimensions ──────────────────────────────────────────────
echo "── Generating competitive dimensions..."

apex "You are a strategic intelligence analyst preparing a competitive research brief on: ${TARGET}

Decompose the competitive landscape into exactly ${AGENTS} orthogonal research dimensions.
Each dimension should be independently researchable and collectively give full coverage.

Draw from these angle categories (select the most relevant ${AGENTS}):
- Market positioning and messaging strategy
- Pricing model, packaging tiers, and value proposition
- Product capabilities, roadmap signals, and feature differentiation
- Developer and user community sentiment (forums, HN, Reddit, reviews)
- Hiring patterns as a signal of strategic investment areas
- Technology stack, infrastructure choices, and engineering culture
- Partnerships, integrations, and ecosystem play
- Funding history, valuation signals, and investor thesis
- Content and SEO strategy — what topics they own
- Known weaknesses, churn signals, and customer complaints

Output exactly ${AGENTS} lines. One dimension per line.
Each line: a specific, actionable research sub-goal for ${TARGET}.
No numbering, no bullets.
Write to ${GOALSFILE} using write_file"

[[ ! -f "$GOALSFILE" ]] && echo "✗ Dimension generation failed" && exit 1

echo "── Research dimensions:"
cat -n "$GOALSFILE"
echo ""

# ── Launch parallel agents ────────────────────────────────────────────────────
echo "── Launching ${AGENTS} agents in parallel..."

PIDS=()
i=0
while IFS= read -r dimension; do
    [[ -z "$dimension" ]] && continue
    AGENT_OUT="$OUTDIR/agent_${i}"
    mkdir -p "$AGENT_OUT"

    (
        export OUTDIR_OVERRIDE="$AGENT_OUT"
        bash "$AGENT_SCRIPT" "$dimension" "$ITER" 2>&1 | \
            sed "s/^/  [intel_${i}] /"
    ) &

    PIDS+=($!)
    echo "   agent_${i} (pid ${PIDS[-1]}): $dimension"
    i=$((i+1))
done < "$GOALSFILE"

echo ""
echo "── Waiting for ${#PIDS[@]} agents..."
for pid in "${PIDS[@]}"; do
    wait "$pid" && echo "   ✓ pid $pid" || echo "   ⚠ pid $pid exited non-zero"
done

# ── Collect reports ───────────────────────────────────────────────────────────
echo ""
echo "── Collecting agent reports..."
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

# ── Strategic synthesis ───────────────────────────────────────────────────────
echo ""
echo "── Synthesising strategic brief..."

RESEARCH_DATE=$(date +"%B %d, %Y")

apex "You are a principal analyst at a strategy consultancy synthesising a competitive brief.
Subject: ${TARGET}
Research date: ${RESEARCH_DATE}

Read the combined agent findings using read_file from ${COMBINED}

Produce a structured strategic intelligence brief in Markdown:

# Competitive Intelligence Brief: ${TARGET}
**Date:** ${RESEARCH_DATE}
**Prepared by:** Axiom LLC

## Executive Summary
(4–6 sentences: who they are, their current trajectory, primary threat/opportunity vector,
and the single most actionable insight for a competitor or investor)

## Market Position & Messaging
(how they frame themselves, who they target, what narrative they own)

## Product & Capabilities
(what they actually do well, key differentiators, notable gaps)

## Pricing & Business Model
(structure, tiers, where they extract value, any predatory or lock-in mechanics)

## Community & Sentiment
(developer/user perception, vocal complaints, loyalty signals, NPS proxies)

## Strategic Signals
(hiring patterns, partnerships, content bets, infrastructure choices — what do these
suggest about their 12–18 month direction?)

## Vulnerabilities & Attack Surface
(where a competitor could credibly win — underserved segments, weak product areas,
pricing pressure points, trust gaps)

## Recommended Watch Items
(3–5 specific signals to monitor going forward, with rationale)

---
*This brief was generated by an autonomous research swarm and is intended as a
structured starting point for human analyst review.*

Rules:
- Specific throughout — company names, product names, numbers, dates
- Resolve conflicts between agents — note genuine disagreement where it exists
- No padding, no generic strategy-speak
- Integrate signals across dimensions — find cross-cutting patterns agents missed individually

Write to ${BRIEF} using write_file"

# ── Spoken summary ────────────────────────────────────────────────────────────
echo ""
echo "── Spoken summary..."

apex "Read the brief using read_file from ${BRIEF}

Extract a 2-sentence spoken summary covering:
- The single most important finding about ${TARGET}
- The top recommended action or watch item

Plain text only, no markdown.
Write to ${SUMMARY} using write_file"

if [[ -f "$SUMMARY" ]]; then
    espeak-ng "$(cat "$SUMMARY")" 2>/dev/null || true
fi

echo ""
echo "✓ Swarm complete"
echo "  Dimensions  : $GOALSFILE"
echo "  Agent dirs  : $OUTDIR/agent_*"
echo "  Combined    : $COMBINED"
echo "  Brief       : $BRIEF"
