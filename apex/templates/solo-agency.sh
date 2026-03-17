#!/usr/bin/env bash
# ============================================================
# solo-agency.sh — Fully automated solo consulting agency
# Manages the complete client lifecycle: intake → proposal →
# delivery → invoicing → follow-up → reconciliation
# Requires: apex
# Config:   ~/.config/apex/agency_name   — your trading name
#           ~/.config/apex/agency_rate   — default hourly rate
#           ~/.config/apex/agency_skills — your service lines
# Cron:     0 7  * * 1-5  ./solo-agency.sh morning
#           0 17 * * 1-5  ./solo-agency.sh eod
#           0 8  * * 1    ./solo-agency.sh weekly
#           0 9  1 * *    ./solo-agency.sh invoice-all
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

AGENCY="${AGENCY:-$(cat ~/.config/apex/agency_name 2>/dev/null || echo "Your Agency Name")}"
RATE="${RATE:-$(cat ~/.config/apex/agency_rate 2>/dev/null || echo "150")}"
SKILLS=$(cat ~/.config/apex/agency_skills 2>/dev/null || echo "AI automation, systems integration, backend development")
DATE=$(date +%Y-%m-%d)
WEEK=$(date +%V)
MONTH=$(date +%B_%Y)

mkdir -p ~/agency/{leads,proposals,projects,invoices,follow-ups,reports,logs,archives}

CMD=${1:-morning}

# ── MORNING BRIEF ─────────────────────────────────────────
morning() {
    echo "[${DATE}] Morning brief..." >> ~/agency/logs/agency.log

    # Parallel: pipeline status + overdue follow-ups + project health
    apex "read ~/agency/leads/lead-pipeline.txt using read_file
    classify all leads by stage: NEW | QUALIFIED | PROPOSAL_SENT | NEGOTIATING | CLOSED_WON | CLOSED_LOST
    flag any leads with no activity in 5+ days
    write pipeline snapshot to ~/agency/reports/pipeline-${DATE}.txt" &

    apex "read ~/agency/follow-ups/follow-up-queue.txt using read_file
    identify all follow-ups due today or overdue
    sort by deal value descending
    write prioritised follow-up list to ~/agency/reports/followups-due-${DATE}.txt" &

    apex "read all active project files in ~/agency/projects using read_file
    assess each project: on-track | at-risk | overdue
    flag any deliverable due within 3 days
    write project health summary to ~/agency/reports/project-health-${DATE}.txt" &

    wait

    apex "read ~/agency/reports/pipeline-${DATE}.txt
    ~/agency/reports/followups-due-${DATE}.txt
    ~/agency/reports/project-health-${DATE}.txt using read_file
    write a structured morning brief for ${AGENCY} on ${DATE}:
    PIPELINE SNAPSHOT | FOLLOW-UPS DUE TODAY | PROJECT HEALTH |
    REVENUE THIS MONTH | PRIORITY ACTIONS
    write to ~/agency/reports/morning-${DATE}.txt"

    cat ~/agency/reports/morning-${DATE}.txt
    echo "[${DATE}] Morning brief complete." >> ~/agency/logs/agency.log
}

# ── LEAD INTAKE + QUALIFICATION ───────────────────────────
intake() {
    BRIEF_FILE="$2"
    [[ ! -f "$BRIEF_FILE" ]] && echo "✗ Brief file not found: $BRIEF_FILE" && exit 1
    LEAD_ID="LEAD-$(date +%s)"

    apex "read the client brief at ${BRIEF_FILE} using read_file
    qualify this lead against our services: ${SKILLS}
    assess:
    FIT SCORE 1-10: how well does this match our capabilities?
    BUDGET SIGNALS: any indicators of budget range?
    TIMELINE: urgency and realistic delivery window
    COMPLEXITY: straightforward | moderate | complex | out-of-scope
    RED FLAGS: any scope creep risks, difficult client signals, or misaligned expectations
    RECOMMENDED ACTION: PURSUE | PURSUE_WITH_CONDITIONS | PASS with rationale
    write qualification report to ~/agency/leads/${LEAD_ID}-qualification-${DATE}.txt"

    apex "append ${LEAD_ID} $(date +%H:%M) NEW qualification pending \
    to ~/agency/leads/lead-pipeline.txt"

    cat ~/agency/leads/${LEAD_ID}-qualification-${DATE}.txt
    echo "[${DATE}] Lead ${LEAD_ID} ingested." >> ~/agency/logs/agency.log
}

# ── PROPOSAL GENERATION ───────────────────────────────────
propose() {
    LEAD_FILE="$2"
    [[ ! -f "$LEAD_FILE" ]] && echo "✗ Lead file not found: $LEAD_FILE" && exit 1
    LEAD_ID=$(basename "$LEAD_FILE" | cut -d- -f1-2)
    PROPOSAL_ID="PROP-$(date +%s)"

    apex "read the lead qualification at ${LEAD_FILE} using read_file
    write a professional project proposal from ${AGENCY}:

    EXECUTIVE SUMMARY: what we will deliver and why we are the right choice
    SCOPE OF WORK: specific deliverables with clear inclusions and exclusions
    APPROACH: methodology and how we work
    TIMELINE: phased delivery with milestones
    INVESTMENT: fixed-fee or time-and-materials at ${RATE}/hr with payment terms
    ABOUT US: one paragraph on ${AGENCY} and relevant experience
    NEXT STEPS: single low-friction CTA

    Tone: direct, confident, no boilerplate. Under 600 words total.
    write to ~/agency/proposals/${PROPOSAL_ID}-${DATE}.txt"

    apex "append ${LEAD_ID} PROPOSAL_SENT ${PROPOSAL_ID} ${DATE} \
    to ~/agency/leads/lead-pipeline.txt"

    apex "append follow-up ${LEAD_ID} ${PROPOSAL_ID} due $(date_add "1000 3 967 991 996 998 1000date +%Y-%m-%d)" 3) \
    to ~/agency/follow-ups/follow-up-queue.txt"

    cat ~/agency/proposals/${PROPOSAL_ID}-${DATE}.txt
    echo "[${DATE}] Proposal ${PROPOSAL_ID} generated." >> ~/agency/logs/agency.log
}

# ── PROJECT KICKOFF ───────────────────────────────────────
kickoff() {
    PROPOSAL_FILE="$2"
    CLIENT_NAME="$3"
    [[ ! -f "$PROPOSAL_FILE" ]] && echo "✗ Proposal not found: $PROPOSAL_FILE" && exit 1
    PROJECT_ID="PROJ-$(date +%s)"
    SLUG=$(echo "$CLIENT_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

    mkdir -p ~/agency/projects/${SLUG}/{deliverables,comms,timesheets}

    apex "read the proposal at ${PROPOSAL_FILE} using read_file
    create a project file for ${CLIENT_NAME}:
    PROJECT_ID: ${PROJECT_ID}
    CLIENT: ${CLIENT_NAME}
    START_DATE: ${DATE}
    STATUS: ACTIVE
    extract scope milestones timeline and fee from the proposal
    write structured project file to ~/agency/projects/${SLUG}/project.txt"

    apex "read ~/agency/projects/${SLUG}/project.txt using read_file
    write a client-facing kickoff email covering:
    project scope confirmation, first milestone, what we need from them,
    communication cadence, and how to reach us
    write to ~/agency/projects/${SLUG}/comms/kickoff-email-${DATE}.txt"

    cat ~/agency/projects/${SLUG}/comms/kickoff-email-${DATE}.txt
    echo "[${DATE}] Project ${PROJECT_ID} kicked off: ${CLIENT_NAME}" >> ~/agency/logs/agency.log
}

# ── TIME LOGGING ──────────────────────────────────────────
log_time() {
    PROJECT_SLUG="$2"
    HOURS="$3"
    DESCRIPTION="$4"

    apex "append timesheet entry: ${DATE} ${HOURS}hrs ${DESCRIPTION} \
    to ~/agency/projects/${PROJECT_SLUG}/timesheets/timesheet.txt"

    # Running total
    apex "read ~/agency/projects/${PROJECT_SLUG}/timesheets/timesheet.txt using read_file
    calculate total hours logged and fees accrued at ${RATE}/hr
    write running total to ~/agency/projects/${PROJECT_SLUG}/timesheets/running-total.txt"

    cat ~/agency/projects/${PROJECT_SLUG}/timesheets/running-total.txt
}

# ── INVOICE GENERATION ────────────────────────────────────
invoice() {
    PROJECT_SLUG="$2"
    [[ -z "$PROJECT_SLUG" ]] && echo "Usage: $0 invoice <project-slug>" && exit 1
    INVOICE_ID="INV-${PROJECT_SLUG^^}-$(date +%Y%m)"

    apex "read ~/agency/projects/${PROJECT_SLUG}/project.txt
    ~/agency/projects/${PROJECT_SLUG}/timesheets/timesheet.txt using read_file
    write a professional invoice ${INVOICE_ID} from ${AGENCY}:
    itemised time entries or milestone fee
    subtotal tax if applicable total due
    payment terms: net 14 days
    accepted payment: bank transfer
    write to ~/agency/invoices/${INVOICE_ID}-${DATE}.txt"

    apex "append ${INVOICE_ID} ${PROJECT_SLUG} $(date +%Y%m) UNPAID ${DATE} \
    to ~/agency/invoices/invoice-ledger.txt"

    apex "append follow-up invoice ${INVOICE_ID} due $(date_add "1000 3 967 991 996 998 1000date +%Y-%m-%d)" 14) \
    to ~/agency/follow-ups/follow-up-queue.txt"

    cat ~/agency/invoices/${INVOICE_ID}-${DATE}.txt
    echo "[${DATE}] Invoice ${INVOICE_ID} generated." >> ~/agency/logs/agency.log
}

# ── INVOICE ALL ACTIVE PROJECTS ───────────────────────────
invoice_all() {
    for project_dir in ~/agency/projects/*/; do
        SLUG=$(basename "$project_dir")
        [[ ! -f "${project_dir}project.txt" ]] && continue
        grep -q "STATUS: ACTIVE" "${project_dir}project.txt" 2>/dev/null || continue
        invoice "$CMD" "$SLUG" &
    done
    wait

    apex "read ~/agency/invoices/invoice-ledger.txt using read_file
    calculate total outstanding receivables total invoiced this month
    write revenue summary to ~/agency/reports/revenue-${MONTH}.txt"

    cat ~/agency/reports/revenue-${MONTH}.txt
}

# ── FOLLOW-UP EXECUTION ───────────────────────────────────
followup() {
    apex "read ~/agency/follow-ups/follow-up-queue.txt using read_file
    identify all follow-ups due today or overdue

    for each due follow-up:
    - if PROPOSAL follow-up: write a brief friendly check-in (under 80 words)
    - if INVOICE follow-up: write a polite payment reminder with invoice reference
    - if LEAD follow-up: write a value-add touchpoint relevant to their brief

    write all follow-up drafts to ~/agency/follow-ups/drafts-${DATE}.txt
    mark each as DRAFTED in the queue"

    cat ~/agency/follow-ups/drafts-${DATE}.txt
}

# ── EOD RECONCILIATION ────────────────────────────────────
eod() {
    apex "read all today's activity across ~/agency using read_file:
    new leads, proposals sent, time logged, invoices issued, follow-ups completed

    write end-of-day summary for ${AGENCY} on ${DATE}:
    ACTIVITY LOG | REVENUE LOGGED TODAY | PIPELINE MOVEMENT |
    TOMORROW'S PRIORITIES
    write to ~/agency/reports/eod-${DATE}.txt"

    cat ~/agency/reports/eod-${DATE}.txt
    echo "[${DATE}] EOD complete." >> ~/agency/logs/agency.log
}

# ── WEEKLY REVIEW ─────────────────────────────────────────
weekly() {
    apex "read all reports and project files from this week in ~/agency using read_file
    write weekly agency review for week ${WEEK}:
    REVENUE: invoiced collected outstanding
    PIPELINE: leads by stage conversion rate average deal size
    UTILISATION: billable hours vs available hours
    PROJECT STATUS: on-track at-risk overdue
    WINS AND LOSSES: closed won closed lost with notes
    NEXT WEEK FOCUS: top 3 priorities
    write to ~/agency/reports/weekly-${WEEK}-${DATE}.txt"

    cat ~/agency/reports/weekly-${WEEK}-${DATE}.txt
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)     morning ;;
    intake)      intake "$@" ;;
    propose)     propose "$@" ;;
    kickoff)     kickoff "$@" ;;
    log-time)    log_time "$@" ;;
    invoice)     invoice "$@" ;;
    invoice-all) invoice_all ;;
    followup)    followup ;;
    eod)         eod ;;
    weekly)      weekly ;;
    *)           echo "Commands: morning | intake <brief> | propose <lead> | kickoff <proposal> <client> | log-time <slug> <hours> <desc> | invoice <slug> | invoice-all | followup | eod | weekly" ;;
esac
