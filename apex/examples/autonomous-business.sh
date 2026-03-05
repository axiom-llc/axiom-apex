#!/usr/bin/env bash
# autonomous-business.sh — A complete operating day, unattended
# Models a solo service business running itself from open to close:
# inbound triage → lead qualification → proposal dispatch →
# project delivery checks → invoice follow-up → EOD P&L
#
# No human in the loop. Run it at 07:00. Read the report at 17:00.
#
# Usage: ./autonomous-business.sh [business_profile] [date_override]
# Example: ./autonomous-business.sh ~/.config/apex/business_profile.txt

set -euo pipefail

PROFILE="${1:-${HOME}/.config/apex/business_profile.txt}"
DATE="${2:-$(date +%Y-%m-%d)}"
DOW=$(date +%A)

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="$HOME/business/$(date +%Y%m%d)"
LOG="$OUTDIR/ops.log"
EOD_REPORT="$OUTDIR/eod-report.md"
PNL="$OUTDIR/pnl-snapshot.txt"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"/{inbound,leads,proposals,projects,invoices,comms,decisions}

echo "▶ Date    : $DATE ($DOW)"
echo "▶ Output  : $OUTDIR"
echo ""

# ── Load business context ─────────────────────────────────
if [[ -f "$PROFILE" ]]; then
    BIZ_CONTEXT=$(cat "$PROFILE")
else
    BIZ_CONTEXT="Solo AI automation consultancy. Services: workflow automation, LLM integration, backend systems. Rate: \$150/hr. Target clients: SMBs and startups. Current capacity: available for new work."
fi

log() { echo "[$(date +%H:%M)] $*" | tee -a "$LOG"; }

# ═════════════════════════════════════════════════════════
# PHASE 1 — MORNING TRIAGE (parallel)
# Read everything that arrived overnight. Classify and prioritise.
# ═════════════════════════════════════════════════════════
log "PHASE 1: Morning triage"
echo ""

INBOUND_SUMMARY="$OUTDIR/inbound/summary.txt"
PIPELINE_SNAPSHOT="$OUTDIR/leads/pipeline-snapshot.txt"
PROJECT_HEALTH="$OUTDIR/projects/health-snapshot.txt"
CASH_POSITION="$OUTDIR/invoices/cash-position.txt"

apex "Business context: ${BIZ_CONTEXT}

Simulate overnight inbound for a solo service business on ${DATE} (${DOW}).
Generate 2-4 realistic inbound items that might arrive overnight:
- Mix of: new enquiry, reply to proposal, support question, invoice payment, referral
- Each should feel like a real message with realistic sender names and content
- At least one should require same-day action

Write each item with: TYPE | FROM | SUBJECT | BODY | URGENCY: HIGH/MEDIUM/LOW
Write to ${INBOUND_SUMMARY} using write_file" &

apex "Business context: ${BIZ_CONTEXT}

Simulate the current sales pipeline state for ${DATE}.
Generate a realistic pipeline with 4-6 leads at different stages:
STAGE: NEW | QUALIFIED | PROPOSAL_SENT | NEGOTIATING | CLOSED_WON | CLOSED_LOST
Include: lead name, company, deal value, days in current stage, last contact date

Flag any leads stalled 5+ days with no movement.
Write pipeline to ${PIPELINE_SNAPSHOT} using write_file" &

apex "Business context: ${BIZ_CONTEXT}

Simulate active project health for ${DATE}.
Generate 2-3 active client projects with realistic status:
Include: project name, client, % complete, next deliverable, due date, hours logged vs estimated
Flag: ON_TRACK | AT_RISK | OVERDUE

Write project health to ${PROJECT_HEALTH} using write_file" &

apex "Business context: ${BIZ_CONTEXT}

Simulate current cash position for ${DATE}.
Generate realistic receivables and payables:
- Outstanding invoices: 2-3 with amounts, issue dates, due dates, status
- Monthly recurring costs: hosting, tools, subscriptions
- Cash on hand estimate
- 30-day revenue forecast based on pipeline

Write cash position to ${CASH_POSITION} using write_file" &

log "  waiting for triage agents..."
wait
log "  triage complete"
echo ""

# ═════════════════════════════════════════════════════════
# PHASE 2 — DECISION ENGINE
# Read all triage output. Produce a prioritised action plan.
# This is the brain of the operating day.
# ═════════════════════════════════════════════════════════
log "PHASE 2: Decision engine"

DAILY_PLAN="$OUTDIR/decisions/daily-plan.txt"

apex "You are the operating intelligence for a solo service business.
Business context: ${BIZ_CONTEXT}
Date: ${DATE} (${DOW})

Read today's situation using read_file:
- Inbound: ${INBOUND_SUMMARY}
- Pipeline: ${PIPELINE_SNAPSHOT}
- Projects: ${PROJECT_HEALTH}
- Cash: ${CASH_POSITION}

Produce a prioritised operating plan for today. For each action:
PRIORITY (1-10) | ACTION_TYPE | TARGET | WHAT TO DO | EXPECTED OUTCOME

Action types: RESPOND | QUALIFY | PROPOSE | FOLLOW_UP | DELIVER | INVOICE | DEFER | IGNORE

Rules:
- Revenue-protecting actions rank highest (invoice follow-up, closing negotiating deals)
- Never defer a HIGH urgency inbound item
- If cash position shows overdue invoices, escalate follow-up priority
- AT_RISK or OVERDUE projects get a delivery check before any sales activity
- Maximum 6 actions — ruthlessly prioritise

Write the ordered action plan to ${DAILY_PLAN} using write_file"

log "  daily plan generated"
echo ""
cat "$DAILY_PLAN"
echo ""

# ═════════════════════════════════════════════════════════
# PHASE 3 — EXECUTION
# Execute each action in the plan in parallel where possible.
# ═════════════════════════════════════════════════════════
log "PHASE 3: Executing actions"

# Action 1: Respond to high-urgency inbound
apex "Read the inbound summary at ${INBOUND_SUMMARY} using read_file.
Read the daily plan at ${DAILY_PLAN} using read_file.

Identify all HIGH urgency inbound items.
For each: draft a professional, human-sounding response under 120 words.
Reference specific details from their message — do not sound templated.

Write all response drafts to ${OUTDIR}/comms/inbound-responses-${DATE}.txt
using write_file" &

# Action 2: Work the pipeline — qualify new leads + follow up stalled ones
apex "Read the pipeline snapshot at ${PIPELINE_SNAPSHOT} using read_file.
Read the business context: ${BIZ_CONTEXT}

For each NEW lead: produce a qualification assessment (fit score 1-10, budget signals, recommended action)
For each lead stalled 5+ days: draft a follow-up message under 80 words
For any NEGOTIATING lead: draft a gentle close or next-step nudge

Write all pipeline actions to ${OUTDIR}/leads/pipeline-actions-${DATE}.txt
using write_file" &

# Action 3: Project delivery check + client update
apex "Read the project health at ${PROJECT_HEALTH} using read_file.

For each AT_RISK or OVERDUE project: draft a proactive client status update
that acknowledges the situation without alarming the client, states the revised
timeline, and requests any blockers be resolved.

For ON_TRACK projects due a milestone this week: draft a brief progress update.

Write all project comms to ${OUTDIR}/projects/client-updates-${DATE}.txt
using write_file" &

# Action 4: Invoice follow-up
apex "Read the cash position at ${CASH_POSITION} using read_file.

For each overdue invoice: draft a payment follow-up.
- 1-14 days overdue: friendly reminder
- 15-29 days overdue: firm reminder with specific payment request
- 30+ days overdue: formal demand with payment deadline

For invoices due within 7 days: draft a courtesy heads-up.

Write all invoice comms to ${OUTDIR}/invoices/follow-ups-${DATE}.txt
using write_file" &

log "  waiting for execution agents..."
wait
log "  execution complete"
echo ""

# ═════════════════════════════════════════════════════════
# PHASE 4 — PROPOSAL GENERATION
# If any qualified leads were identified, generate proposals.
# Runs after execution so qualification output is available.
# ═════════════════════════════════════════════════════════
log "PHASE 4: Proposal generation"

QUALIFIED_LEADS="$OUTDIR/leads/pipeline-actions-${DATE}.txt"

apex "Read the pipeline actions at ${QUALIFIED_LEADS} using read_file.
Business context: ${BIZ_CONTEXT}

Identify any leads recommended for PROPOSE.

For each: write a concise project proposal:
- Executive summary (2 sentences)
- Scope of work (specific deliverables, clear exclusions)
- Timeline (phases with milestones)
- Investment (fixed fee or hourly estimate)
- Single CTA

Under 500 words per proposal. Direct and confident — no boilerplate.

Write all proposals to ${OUTDIR}/proposals/proposals-${DATE}.txt using write_file"

log "  proposals generated"
echo ""

# ═════════════════════════════════════════════════════════
# PHASE 5 — EOD RECONCILIATION + P&L SNAPSHOT
# Read everything that happened today. Produce the EOD report.
# ═════════════════════════════════════════════════════════
log "PHASE 5: EOD reconciliation"

apex "You are producing the end-of-day operating report for a solo service business.
Business context: ${BIZ_CONTEXT}
Date: ${DATE} (${DOW})

Read all of today's outputs using read_file:
${INBOUND_SUMMARY}
${PIPELINE_SNAPSHOT}
${PROJECT_HEALTH}
${CASH_POSITION}
${DAILY_PLAN}
${OUTDIR}/comms/inbound-responses-${DATE}.txt
${OUTDIR}/leads/pipeline-actions-${DATE}.txt
${OUTDIR}/projects/client-updates-${DATE}.txt
${OUTDIR}/invoices/follow-ups-${DATE}.txt
${OUTDIR}/proposals/proposals-${DATE}.txt

Write a complete EOD report in Markdown:

# Operating Report — ${DATE}

## Day Summary
(3 sentences: what happened today, what moved, what got done)

## Actions Taken
(table: Action | Target | Status | Expected Outcome)

## Pipeline Movement
(leads advanced, stalled, closed — net pipeline value change)

## Revenue Activity
(invoices followed up, proposals sent, deals closed — total value in motion)

## Project Status
(each active project: status change if any, next milestone)

## Cash Position
(receivables outstanding, overdue amounts, 30-day forecast)

## Tomorrow's Priorities
(top 3 actions ranked by revenue impact)

## Decisions Made
(any leads deferred, ignored, or disqualified — with rationale)

Write to ${EOD_REPORT} using write_file"

# P&L snapshot — separate file, numbers only
apex "Read the cash position at ${CASH_POSITION} and the EOD report
at ${EOD_REPORT} using read_file.

Extract a plain-text P&L snapshot for ${DATE}:
RECEIVABLES OUTSTANDING: total \$
OVERDUE (30+ days): total \$
PROPOSALS IN FLIGHT: count and total potential value \$
PIPELINE VALUE: total qualified pipeline \$
MONTHLY RECURRING COSTS: \$
30-DAY REVENUE FORECAST: \$
RUNWAY ESTIMATE: X months at current burn

Numbers only — no prose.
Write to ${PNL} using write_file"

log "  EOD reconciliation complete"
echo ""

# ═════════════════════════════════════════════════════════
# OUTPUT
# ═════════════════════════════════════════════════════════
echo "══════════════════════════════════════════"
echo "  AUTONOMOUS BUSINESS — ${DATE}"
echo "══════════════════════════════════════════"
echo ""
cat "$EOD_REPORT"
echo ""
echo "── P&L Snapshot ──"
cat "$PNL"
echo ""
echo "✓ Operating day complete"
echo "  Full output : $OUTDIR"
echo "  EOD report  : $EOD_REPORT"
echo "  Ops log     : $LOG"
