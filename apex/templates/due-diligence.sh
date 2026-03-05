#!/usr/bin/env bash
# ============================================================
# due-diligence.sh — M&A and investment due diligence automation
# Requires: apex
# Usage:    ./due-diligence.sh "Company Name" [deal_type] [agents]
# Examples: ./due-diligence.sh "Acme Corp" acquisition 6
#           ./due-diligence.sh "FinTech Startup" investment 5
# ============================================================
set -euo pipefail

TARGET="${1:-}"
DEAL_TYPE="${2:-acquisition}"
AGENTS="${3:-6}"

[[ -z "$TARGET" ]] && echo "Usage: $0 \"Company Name\" [acquisition|investment|partnership] [agents]" && exit 1

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_SCRIPT="$(dirname "$0")/../examples/research-agent.sh"
DATE=$(date +%Y-%m-%d)
OUTDIR="$HOME/diligence/$(echo "$TARGET" | tr ' ' '_')-${DATE}"
DIMENSIONS="$OUTDIR/dimensions.txt"
COMBINED="$OUTDIR/combined.txt"
MEMO="$OUTDIR/diligence-memo.md"
REDFLAGS="$OUTDIR/red-flags.txt"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"/{agents,findings,memo}

echo "▶ Target    : $TARGET"
echo "▶ Deal type : $DEAL_TYPE"
echo "▶ Agents    : $AGENTS"
echo "▶ Output    : $OUTDIR"
echo ""

# ── Generate diligence dimensions ────────────────────────
echo "── Defining diligence scope..."

apex "You are a managing director at a top-tier M&A advisory firm.
Target: ${TARGET}
Deal type: ${DEAL_TYPE}

Define exactly ${AGENTS} due diligence research dimensions appropriate for a ${DEAL_TYPE}.
Each dimension must be independently researchable via public sources.
Draw from these categories as appropriate:

FINANCIAL: revenue model, growth rate, burn rate, unit economics, debt obligations
LEGAL: litigation history, IP ownership, regulatory actions, contract obligations
MARKET: TAM/SAM, competitive position, customer concentration, churn signals
TECHNOLOGY: stack assessment, technical debt signals, security posture, scalability
MANAGEMENT: founder/executive background, key person risk, team depth, culture signals
REGULATORY: industry regulations, compliance history, licensing requirements
REPUTATION: press coverage, customer sentiment, employee reviews, social signals

Output exactly ${AGENTS} lines. One per line. Each a specific, actionable research goal.
No numbering, no bullets.
Write to ${DIMENSIONS} using write_file"

[[ ! -f "$DIMENSIONS" ]] && echo "✗ Scope definition failed" && exit 1

echo "── Diligence dimensions:"
cat -n "$DIMENSIONS"
echo ""

# ── Launch parallel research agents ──────────────────────
echo "── Launching ${AGENTS} parallel diligence agents..."

PIDS=()
i=0
while IFS= read -r dimension; do
    [[ -z "$dimension" ]] && continue
    AGENT_OUT="$OUTDIR/agents/agent_${i}"
    mkdir -p "$AGENT_OUT"
    (
        export OUTDIR_OVERRIDE="$AGENT_OUT"
        bash "$AGENT_SCRIPT" "${TARGET}: ${dimension}" 10 2>&1 | \
            sed "s/^/  [dd_${i}] /"
    ) &
    PIDS+=($!)
    echo "   agent_${i} (pid ${PIDS[-1]}): $dimension"
    i=$((i+1))
done < "$DIMENSIONS"

echo ""
echo "── Waiting for ${#PIDS[@]} agents to complete..."
for pid in "${PIDS[@]}"; do
    wait "$pid" && echo "   ✓ pid $pid" || echo "   ⚠ pid $pid exited non-zero"
done

# ── Collect findings ──────────────────────────────────────
echo ""
echo "── Collecting findings..."
> "$COMBINED"

for j in $(seq 0 $((AGENTS-1))); do
    AGENT_REPORT=$(find "$OUTDIR/agents/agent_${j}" -name "report.md" 2>/dev/null | head -1)
    if [[ -f "$AGENT_REPORT" ]]; then
        echo "=== DIMENSION ${j} ===" >> "$COMBINED"
        cat "$AGENT_REPORT" >> "$COMBINED"
        echo "" >> "$COMBINED"
        echo "   ✓ agent_${j}"
    else
        echo "   ⚠ agent_${j} — no report"
    fi
done

# ── Red flag extraction (fast, parallel with memo) ────────
echo ""
echo "── Extracting red flags..."

apex "You are a deal risk analyst.
Read the combined diligence findings using read_file from ${COMBINED}

Extract ONLY material red flags — issues that could:
- Kill the deal
- Require price adjustment
- Require escrow or indemnification
- Create post-close liability

Format each red flag:
CATEGORY | SEVERITY: HIGH/MEDIUM | FINDING | IMPLICATION | SUGGESTED MITIGATION

Write to ${REDFLAGS} using write_file" &

# ── Diligence memo ────────────────────────────────────────
echo "── Writing diligence memo..."

apex "You are a managing director writing a diligence memo for an investment committee.
Target: ${TARGET}
Deal type: ${DEAL_TYPE}
Date: ${DATE}

Read the combined findings using read_file from ${COMBINED}

Write a professional diligence memo in Markdown:

# Due Diligence Memo: ${TARGET}
**Date:** ${DATE} | **Deal Type:** ${DEAL_TYPE} | **Prepared by:** Axiom LLC

## Investment Committee Summary
(5-6 sentences: what the company does, current state, deal rationale,
primary opportunity, primary risk, and preliminary recommendation)

## Business Overview
(market position, business model, revenue profile, growth trajectory)

## Financial Assessment
(revenue, growth rate, unit economics, burn/runway if applicable, key metrics)

## Market & Competitive Position
(TAM, share, moat, competitive threats, customer concentration)

## Technology & Operations
(stack assessment, scalability, technical debt, key person dependencies)

## Legal & Regulatory
(material litigation, IP status, regulatory exposure, compliance posture)

## Management Assessment
(founder/executive track record, team depth, key person risk, culture signals)

## Material Risks
(ranked by severity — deal killers first)

## Recommended Deal Structure
(price, structure, key provisions, reps & warranties focus areas)

## Preliminary Recommendation
PROCEED | PROCEED WITH CONDITIONS | PASS — with clear rationale

---
*This memo was produced by an autonomous research process and requires human analyst review
before presentation to investment committee.*

Write to ${MEMO} using write_file"

wait

echo ""
echo "── Red flags:"
cat "$REDFLAGS"
echo ""
echo "✓ Due diligence complete"
echo "  Memo      : $MEMO"
echo "  Red flags : $REDFLAGS"
echo "  Findings  : $COMBINED"
