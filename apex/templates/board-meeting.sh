#!/usr/bin/env bash
# ============================================================
# board-meeting.sh — Board deck narrative generator
# Requires: apex
# Config:   echo "Axiom LLC" > ~/.config/apex/company_name
#           echo "SaaS" > ~/.config/apex/company_type
# Usage:    ./board-meeting.sh "metrics_file" "incidents_file" "updates_file" [quarter]
# Example:  ./board-meeting.sh ~/board/metrics.txt ~/board/incidents.txt ~/board/updates.txt Q2-2025
# ============================================================
set -euo pipefail

METRICS="${1:-}"
INCIDENTS="${2:-}"
UPDATES="${3:-}"
QUARTER="${4:-$(date +Q%q-%Y)}"
COMPANY=$(cat ~/.config/apex/company_name 2>/dev/null || echo "The Company")
TYPE=$(cat ~/.config/apex/company_type 2>/dev/null || echo "SaaS")
DATE=$(date +%Y-%m-%d_%H%M%S)
mkdir -p ~/board/{sections,narrative,final,logs}

if [[ -z "$METRICS" || -z "$INCIDENTS" || -z "$UPDATES" ]]; then
    echo "Usage: $0 metrics.txt incidents.txt updates.txt [quarter]"
    exit 1
fi

echo "▶ Company  : $COMPANY ($TYPE)"
echo "▶ Quarter  : $QUARTER"
echo ""

# ── PHASE 1: INPUT ANALYSIS (parallel) ────────────────────
echo "── Analysing inputs in parallel..."

apex "read ${METRICS} using read_file \
interpret all metrics in the context of a ${TYPE} company called ${COMPANY} \
identify: MoM and QoQ trends, metrics above/below benchmark, leading indicators, \
any metric that tells a different story than the others \
write analysis to ~/board/sections/metrics-analysis-${DATE}.txt" &

apex "read ${INCIDENTS} using read_file \
classify each incident by severity, customer impact, and resolution quality \
identify systemic patterns across incidents \
assess overall operational maturity signal \
write analysis to ~/board/sections/incident-analysis-${DATE}.txt" &

apex "read ${UPDATES} using read_file \
extract product and business updates, categorise by: \
shipped features, strategic moves, partnership or customer wins, \
team changes, and items that carry forward risk \
write analysis to ~/board/sections/updates-analysis-${DATE}.txt" &

wait

# ── PHASE 2: NARRATIVE SECTIONS (parallel) ────────────────
echo "── Generating board narrative sections in parallel..."

apex "read ~/board/sections/metrics-analysis-${DATE}.txt using read_file \
write the EXECUTIVE SUMMARY section for a board deck: \
3 paragraphs, opens with the single most important number, \
tells the story of ${QUARTER} in plain language a non-technical board member understands, \
ends with a clear statement of where the company stands today \
write to ~/board/sections/exec-summary-${DATE}.txt" &

apex "read ~/board/sections/metrics-analysis-${DATE}.txt using read_file \
write the KPI COMMENTARY section: \
for each key metric, one paragraph: what happened, why, what it means going forward \
flag any metric where the explanation is uncertain — label [NEEDS CONTEXT] \
write to ~/board/sections/kpi-commentary-${DATE}.txt" &

apex "read ~/board/sections/incident-analysis-${DATE}.txt using read_file \
write the OPERATIONAL HEALTH section: \
incident summary, systemic patterns identified, remediation status, \
honest assessment of engineering reliability posture \
no whitewashing — board members can handle the truth \
write to ~/board/sections/ops-health-${DATE}.txt" &

apex "read ~/board/sections/updates-analysis-${DATE}.txt using read_file \
write the PRODUCT AND BUSINESS UPDATES section: \
what shipped and why it matters, what won and what the win signals, \
what is at risk and what is being done about it \
write to ~/board/sections/updates-narrative-${DATE}.txt" &

apex "read ~/board/sections/metrics-analysis-${DATE}.txt \
~/board/sections/incident-analysis-${DATE}.txt \
~/board/sections/updates-analysis-${DATE}.txt using read_file \
write the RISK REGISTER section: \
top 5 risks, each with: risk description, likelihood (H/M/L), impact (H/M/L), \
current mitigation, owner, and status (OPEN/MITIGATED/ACCEPTED) \
write to ~/board/sections/risk-register-${DATE}.txt" &

apex "read ~/board/sections/metrics-analysis-${DATE}.txt \
~/board/sections/updates-analysis-${DATE}.txt using read_file \
write the FORWARD GUIDANCE section: \
next quarter targets with confidence levels, \
key assumptions those targets depend on, \
one scenario where we beat guidance and one where we miss — what drives each \
write to ~/board/sections/guidance-${DATE}.txt" &

wait

# ── PHASE 3: FULL DECK NARRATIVE ──────────────────────────
echo "── Assembling full board narrative..."

apex "read all section files from ~/board/sections/ that contain ${DATE} using read_file \
assemble into a complete board meeting narrative document for ${COMPANY} ${QUARTER}: \
EXECUTIVE SUMMARY | KPI COMMENTARY | OPERATIONAL HEALTH | \
PRODUCT AND BUSINESS UPDATES | RISK REGISTER | FORWARD GUIDANCE \
ensure transitions between sections are coherent \
tone: direct, honest, confident — this is for a board, not a press release \
write to ~/board/narrative/deck-${DATE}.md"

# ── PHASE 4: TALKING POINTS ───────────────────────────────
apex "read ~/board/narrative/deck-${DATE}.md using read_file \
write a CEO talking points document: \
for each section, 3-5 bullet points the CEO should be prepared to speak to, \
including the 3 questions the board is most likely to ask and suggested answers \
write to ~/board/final/talking-points-${DATE}.txt"

echo ""
echo "✓ Board package complete"
echo "  Full narrative  : ~/board/narrative/deck-${DATE}.md"
echo "  Talking points  : ~/board/final/talking-points-${DATE}.txt"
echo "  Sections        : ~/board/sections/"
