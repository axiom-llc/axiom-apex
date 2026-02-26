#!/bin/bash
# ============================================================
# APEX INTEGRATION TEMPLATE — LAW FIRM
# Version: 1.0
# Author: [Your Name] — Independent IT Consultant
# Client: [Firm Name]
# ============================================================
# DIRECTORY STRUCTURE:
#   ~/firm/
#     matters/          # Active matter logs (one file per matter)
#     billing/          # Daily billing summaries
#     deadlines/        # Deadline tracker files
#     reports/          # Weekly/monthly generated reports
#     audio/            # Narrated briefings
#     drafts/           # Auto-generated document drafts
#     archives/         # Rotated historical data
#     logs/             # Script execution logs
# ============================================================
# CRON SCHEDULE:
#   0 7  * * 1-5   daily-brief.sh        # Weekday morning brief
#   0 17 * * 1-5   end-of-day.sh         # Weekday EOD summary
#   0 8  * * 1     weekly-review.sh      # Monday weekly review
#   0 9  1 * *     monthly-report.sh     # First of month report
# ============================================================

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
WEEK=$(date +%V)
FIRM="[Firm Name]"

mkdir -p ~/firm/{matters,billing,deadlines,reports,audio,drafts,archives,logs}

# ── USAGE ─────────────────────────────────────────────────
# Run full daily brief:       ./apex-template-lawfirm.sh brief
# Run EOD summary:            ./apex-template-lawfirm.sh eod
# Run weekly review:          ./apex-template-lawfirm.sh weekly
# New matter intake:          ./apex-template-lawfirm.sh intake "MATTER-042" "Client Name" "Case Type"
# Log billing entry:          ./apex-template-lawfirm.sh bill "MATTER-042" "3.5" "Contract review and redline"
# Add deadline:               ./apex-template-lawfirm.sh deadline "MATTER-042" "2024-03-15" "Motion filing deadline"

CMD=${1:-brief}

# ── DAILY MORNING BRIEF ───────────────────────────────────
daily_brief() {
    echo "[$(date)] Running daily brief..." >> ~/firm/logs/script.log

    # Snapshot active matters
    apex "read all files in ~/firm/matters and write a summary of all active matters \
    with client names case types and last activity dates to ~/firm/reports/active-matters-${DATE}.txt"

    # Deadline alerts — parallel
    apex "read ~/firm/deadlines/deadlines.txt and identify any deadlines within the next 7 days \
    and write urgent alerts to ~/firm/deadlines/urgent-${DATE}.txt" &

    apex "read ~/firm/billing/billing-log.txt and calculate total hours billed this week \
    and write summary to ~/firm/billing/week-summary-${DATE}.txt" &

    wait

    # Consolidate brief
    apex "read ~/firm/reports/active-matters-${DATE}.txt \
    ~/firm/deadlines/urgent-${DATE}.txt \
    ~/firm/billing/week-summary-${DATE}.txt \
    and write a structured ${DAY} morning brief for ${FIRM} \
    with sections for urgent deadlines active matters and billing status \
    to ~/firm/reports/daily-brief-${DATE}.txt"

    # Narrate brief
    apex "read ~/firm/reports/daily-brief-${DATE}.txt \
    and use espeak in a professional BBC news anchor voice at speed 140 \
    and save to ~/firm/audio/daily-brief-${DATE}.wav"

    aplay ~/firm/audio/daily-brief-${DATE}.wav 2>/dev/null

    echo "[$(date)] Daily brief complete." >> ~/firm/logs/script.log
}

# ── END OF DAY SUMMARY ────────────────────────────────────
end_of_day() {
    echo "[$(date)] Running EOD summary..." >> ~/firm/logs/script.log

    apex "read ~/firm/billing/billing-log.txt and summarize all billing entries \
    logged today ${DATE} including total hours by matter \
    to ~/firm/billing/eod-${DATE}.txt"

    apex "write an end of day summary for ${DATE} at ${FIRM} incorporating \
    billing totals from ~/firm/billing/eod-${DATE}.txt \
    and any deadline changes from ~/firm/deadlines/deadlines.txt \
    to ~/firm/reports/eod-${DATE}.txt"

    apex "read ~/firm/reports/eod-${DATE}.txt \
    and use espeak in a calm professional voice at speed 135 \
    and save to ~/firm/audio/eod-${DATE}.wav"

    aplay ~/firm/audio/eod-${DATE}.wav 2>/dev/null

    echo "[$(date)] EOD summary complete." >> ~/firm/logs/script.log
}

# ── WEEKLY REVIEW ─────────────────────────────────────────
weekly_review() {
    echo "[$(date)] Running weekly review..." >> ~/firm/logs/script.log

    PREV_WEEK=$(date -d "last week" +%Y-%m-%d)

    # Parallel report generation
    apex "read ~/firm/billing/billing-log.txt and generate a full billing report \
    for week ${WEEK} with hours per matter per attorney and total revenue estimate \
    to ~/firm/reports/weekly-billing-${DATE}.txt" &

    apex "read all files in ~/firm/matters and generate a matter status report \
    flagging any matters with no activity in 7 or more days \
    to ~/firm/reports/weekly-matters-${DATE}.txt" &

    apex "read ~/firm/deadlines/deadlines.txt and generate a two week deadline \
    lookahead calendar sorted by urgency \
    to ~/firm/reports/weekly-deadlines-${DATE}.txt" &

    wait

    # Consolidated weekly report
    apex "read ~/firm/reports/weekly-billing-${DATE}.txt \
    ~/firm/reports/weekly-matters-${DATE}.txt \
    ~/firm/reports/weekly-deadlines-${DATE}.txt \
    and write a comprehensive weekly review report for week ${WEEK} at ${FIRM} \
    with executive summary billing analysis matter health and upcoming deadlines \
    to ~/firm/reports/weekly-review-${DATE}.txt"

    # Narrate
    apex "read ~/firm/reports/weekly-review-${DATE}.txt \
    and use espeak in Morgan Freeman's voice at speed 130 pitch 35 \
    and save to ~/firm/audio/weekly-review-${DATE}.wav"

    aplay ~/firm/audio/weekly-review-${DATE}.wav 2>/dev/null

    # Archive last week's daily files
    apex "archive all daily report files in ~/firm/reports older than 7 days \
    into ~/firm/archives/week-${WEEK}-reports.tar.gz \
    then use espeak to say weekly review complete and archived"

    echo "[$(date)] Weekly review complete." >> ~/firm/logs/script.log
}

# ── MATTER INTAKE ─────────────────────────────────────────
new_matter_intake() {
    MATTER_ID=$2
    CLIENT=$3
    CASE_TYPE=$4

    echo "[$(date)] New matter intake: ${MATTER_ID}" >> ~/firm/logs/script.log

    apex "write a new matter file for matter ${MATTER_ID} client ${CLIENT} \
    case type ${CASE_TYPE} opened ${DATE} with sections for case summary \
    key dates parties involved and notes to ~/firm/matters/${MATTER_ID}.txt"

    apex "append a new entry to ~/firm/deadlines/deadlines.txt \
    for matter ${MATTER_ID} client ${CLIENT} opened ${DATE} with placeholder deadlines"

    apex "write a new matter opening letter template for client ${CLIENT} \
    matter ${MATTER_ID} case type ${CASE_TYPE} dated ${DATE} \
    to ~/firm/drafts/opening-letter-${MATTER_ID}.txt"

    apex "use espeak to say new matter ${MATTER_ID} for ${CLIENT} has been created"
}

# ── BILLING ENTRY ─────────────────────────────────────────
log_billing() {
    MATTER_ID=$2
    HOURS=$3
    DESCRIPTION=$4

    apex "append a billing entry to ~/firm/billing/billing-log.txt \
    with date ${DATE} matter ${MATTER_ID} hours ${HOURS} description ${DESCRIPTION}"

    apex "use espeak to say billing entry logged: ${HOURS} hours on matter ${MATTER_ID}"
}

# ── DEADLINE ENTRY ────────────────────────────────────────
add_deadline() {
    MATTER_ID=$2
    DEADLINE_DATE=$3
    DESCRIPTION=$4

    apex "append a deadline entry to ~/firm/deadlines/deadlines.txt \
    with matter ${MATTER_ID} deadline date ${DEADLINE_DATE} \
    description ${DESCRIPTION} added ${DATE}"

    apex "use espeak to say deadline added for matter ${MATTER_ID} due ${DEADLINE_DATE}"
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    brief)    daily_brief ;;
    eod)      end_of_day ;;
    weekly)   weekly_review ;;
    intake)   new_matter_intake "$@" ;;
    bill)     log_billing "$@" ;;
    deadline) add_deadline "$@" ;;
    *)        echo "Unknown command: $CMD" ;;
esac
