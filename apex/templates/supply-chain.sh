#!/usr/bin/env bash
# ============================================================
# supply-chain.sh — Vendor and supplier risk monitor
# Requires: apex
# Config:   ~/.config/apex/vendors — one vendor name per line
#           ~/.config/apex/supply_context — your industry/exposure
# Cron:     0 8 * * 1-5 ~/path/to/supply-chain.sh >> ~/supply/logs/supply.log 2>&1
# ============================================================
set -euo pipefail

VENDOR_FILE="${1:-${HOME}/.config/apex/vendors}"
CONTEXT=$(cat ~/.config/apex/supply_context 2>/dev/null || echo "technology services")
DATE=$(date +%Y-%m-%d)
mkdir -p ~/supply/{signals,risk,alerts,reports,logs,archives}

[[ ! -f "$VENDOR_FILE" ]] && echo "✗ Vendor list not found: $VENDOR_FILE" && exit 1

VENDORS=($(grep -v '^\s*$' "$VENDOR_FILE"))
TOTAL=${#VENDORS[@]}
echo "▶ Vendors  : $TOTAL"
echo "▶ Context  : $CONTEXT"
echo ""

# ── PHASE 1: PARALLEL VENDOR SIGNAL COLLECTION ────────────
echo "── Scanning ${TOTAL} vendors in parallel..."

PIDS=()
for vendor in "${VENDORS[@]}"; do
    slug=$(echo "$vendor" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
    query=$(echo "$vendor" | tr ' ' '+')
    (
        apex "fetch https://hn.algolia.com/api/v1/search?query=${query}&tags=story \
        using http_get \
        extract stories mentioning ${vendor} from the last 30 days \
        write to ~/supply/signals/${slug}-hn-${DATE}.txt"

        apex "fetch https://www.google.com/search?q=${query}+news+risk+outage+breach+lawsuit+bankruptcy+2024+2025 \
        using http_get \
        extract news headlines and summaries mentioning ${vendor} \
        write to ~/supply/signals/${slug}-news-${DATE}.txt"
    ) &
    PIDS+=($!)
done

for pid in "${PIDS[@]}"; do wait "$pid" || true; done
echo "   ✓ signals collected"

# ── PHASE 2: PARALLEL RISK SCORING ────────────────────────
echo "── Scoring vendor risk in parallel..."

PIDS=()
for vendor in "${VENDORS[@]}"; do
    slug=$(echo "$vendor" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
    (
        apex "read ~/supply/signals/${slug}-hn-${DATE}.txt \
        ~/supply/signals/${slug}-news-${DATE}.txt using read_file \
        assess risk for vendor: ${vendor} in context of: ${CONTEXT} \
        score each risk dimension 1-10: \
        FINANCIAL_STABILITY | OPERATIONAL_RELIABILITY | GEOPOLITICAL_EXPOSURE | \
        REGULATORY_RISK | REPUTATIONAL_RISK | SUPPLY_CONCENTRATION \
        flag as: GREEN (no concerns) | YELLOW (monitor) | RED (action required) \
        cite specific signals that drove each flag \
        write to ~/supply/risk/${slug}-score-${DATE}.txt"
    ) &
    PIDS+=($!)
done

for pid in "${PIDS[@]}"; do wait "$pid" || true; done
echo "   ✓ risk scores complete"

# ── PHASE 3: ALERT GENERATION ─────────────────────────────
echo "── Generating alerts for RED flags..."

for vendor in "${VENDORS[@]}"; do
    slug=$(echo "$vendor" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
    score_file=~/supply/risk/${slug}-score-${DATE}.txt
    [[ ! -f "$score_file" ]] && continue

    if grep -q "RED" "$score_file" 2>/dev/null; then
        apex "read ${score_file} using read_file \
        write an actionable alert for vendor: ${vendor} \
        include: what the risk is, what triggered the flag, \
        recommended immediate action (pause orders / find alternative / escalate / monitor) \
        write to ~/supply/alerts/${slug}-ALERT-${DATE}.txt"
    fi
done

# ── PHASE 4: PORTFOLIO REPORT ─────────────────────────────
apex "read all score files in ~/supply/risk/ that contain ${DATE} using read_file \
and all alert files in ~/supply/alerts/ that contain ${DATE} using read_file \
write a supply chain risk report for ${DATE} with sections: \
EXECUTIVE SUMMARY (overall portfolio risk posture) | \
RED FLAGS (vendors requiring immediate action) | \
YELLOW FLAGS (vendors to monitor) | \
GREEN (stable vendors) | \
CONCENTRATION RISK (any single-vendor dependency exposure) | \
RECOMMENDED ACTIONS (prioritised, specific) \
write to ~/supply/reports/report-${DATE}.md"

# ── PHASE 5: DELTA FROM YESTERDAY ─────────────────────────
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
PREV_REPORT=~/supply/reports/report-${YESTERDAY}.md

if [[ -f "$PREV_REPORT" ]]; then
    apex "read today's report from ~/supply/reports/report-${DATE}.md \
    and yesterday's report from ${PREV_REPORT} using read_file \
    write a change summary: which vendors changed status since yesterday, \
    what new risks emerged, what risks resolved \
    write to ~/supply/reports/delta-${DATE}.txt"
    echo ""
    cat ~/supply/reports/delta-${DATE}.txt
fi

echo ""
cat ~/supply/reports/report-${DATE}.md
echo ""
echo "  Signals : ~/supply/signals/"
echo "  Scores  : ~/supply/risk/"
echo "  Alerts  : ~/supply/alerts/"
echo "  Report  : ~/supply/reports/report-${DATE}.md"

# ── PHASE 6: ARCHIVE ──────────────────────────────────────
ARCHIVE=~/supply/archives/${YESTERDAY}.tar.gz
if [[ ! -f "$ARCHIVE" ]]; then
    find ~/supply/{signals,risk,alerts,reports} \
        -maxdepth 1 -name "*${YESTERDAY}*" -print0 | \
        tar czf "$ARCHIVE" --null -T - 2>/dev/null || true
fi
