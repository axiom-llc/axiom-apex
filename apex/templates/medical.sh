#!/usr/bin/env bash
# ============================================================
# APEX INTEGRATION TEMPLATE — MEDICAL / DENTAL PRACTICE
# Version: 1.0
# Axiom LLC
# ============================================================
# IMPORTANT: All data stays LOCAL. No cloud transmission.
# This template is designed for on-premise deployment only.
# Consult your local HIPAA/GDPR compliance requirements.
# ============================================================
# DIRECTORY STRUCTURE:
#   ~/practice/
#     schedule/         # Daily appointment schedules
#     patients/         # Patient notes (anonymized IDs only)
#     billing/          # Billing and insurance claim logs
#     inventory/        # Medical/dental supplies stock
#     reports/          # Generated operational reports
#     compliance/       # Audit logs and compliance records
#     audio/            # Narrated staff briefings
#     letters/          # Auto-generated patient letters
#     logs/             # Script execution logs
# ============================================================
# CRON SCHEDULE:
#   0 7  * * 1-5   ./apex-practice.sh morning
#   0 12 * * 1-5   ./apex-practice.sh midday
#   0 17 * * 1-5   ./apex-practice.sh eod
#   0 8  * * 1     ./apex-practice.sh weekly
#   0 2  * * *     ./apex-practice.sh compliance-audit
#   0 9  1 * *     ./apex-practice.sh monthly
# ============================================================

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
WEEK=$(date +%V)
MONTH=$(date +%B)
PRACTICE="[Practice Name]"

mkdir -p ~/practice/{schedule,patients,billing,inventory,reports,compliance,audio,letters,logs}

CMD=${1:-morning}

# ── MORNING BRIEF ─────────────────────────────────────────
morning_brief() {
    apex "read ~/practice/schedule/appointments-${DATE}.txt \
    and summarize total appointments by time slot provider \
    and appointment type \
    and write to ~/practice/reports/schedule-summary-${DATE}.txt" &

    apex "read ~/practice/inventory/stock-levels.txt \
    and identify any supplies below minimum threshold \
    and write alerts to ~/practice/inventory/low-stock-${DATE}.txt" &

    apex "read ~/practice/billing/outstanding-claims.txt \
    and identify any claims outstanding more than 30 days \
    and write to ~/practice/billing/overdue-claims-${DATE}.txt" &

    wait

    apex "read ~/practice/reports/schedule-summary-${DATE}.txt \
    ~/practice/inventory/low-stock-${DATE}.txt \
    ~/practice/billing/overdue-claims-${DATE}.txt \
    and write a structured ${DAY} morning operations brief for ${PRACTICE} \
    with sections for today's schedule supply alerts and billing status \
    DO NOT include any patient names or identifiable information \
    to ~/practice/reports/morning-brief-${DATE}.txt"

    apex "read ~/practice/reports/morning-brief-${DATE}.txt \
    and use espeak in a professional clinical voice at speed 140 \
    and save to ~/practice/audio/morning-brief-${DATE}.wav"

    aplay ~/practice/audio/morning-brief-${DATE}.wav 2>/dev/null
}

# ── MIDDAY BRIEF ──────────────────────────────────────────
midday_brief() {
    apex "read ~/practice/schedule/appointments-${DATE}.txt \
    and extract afternoon appointments by provider \
    and write to ~/practice/reports/afternoon-schedule-${DATE}.txt"

    apex "read ~/practice/reports/afternoon-schedule-${DATE}.txt \
    and use espeak at speed 145 and save to \
    ~/practice/audio/midday-brief-${DATE}.wav"

    aplay ~/practice/audio/midday-brief-${DATE}.wav 2>/dev/null
}

# ── GENERATE RECALL LETTERS ───────────────────────────────
generate_recall_letters() {
    BATCH=$2   # path to list of patient IDs due for recall

    apex "read ${BATCH} \
    and for each patient ID write a professional recall letter \
    reminding them their routine checkup is due \
    using generic patient reference numbers only no names in filenames \
    save each to ~/practice/letters/recall-[ID]-${DATE}.txt"

    COUNT=$(wc -l < "$BATCH" 2>/dev/null || echo 0)
    apex "use espeak to say ${COUNT} recall letters generated for ${DATE}"
}

# ── LOG BILLING ENTRY ─────────────────────────────────────
log_billing() {
    PATIENT_ID=$2
    PROCEDURE=$3
    AMOUNT=$4
    INSURER=$5

    apex "append billing entry patient ${PATIENT_ID} procedure ${PROCEDURE} \
    amount ${AMOUNT} insurer ${INSURER} date ${DATE} status PENDING \
    to ~/practice/billing/billing-log.txt"

    apex "append claim patient ${PATIENT_ID} insurer ${INSURER} \
    amount ${AMOUNT} submitted ${DATE} \
    to ~/practice/billing/outstanding-claims.txt"
}

# ── SUPPLY REORDER ────────────────────────────────────────
reorder_supplies() {
    apex "read ~/practice/inventory/stock-levels.txt \
    ~/practice/inventory/suppliers.txt \
    and generate a reorder list for all items below minimum threshold \
    with supplier details order quantities and estimated cost \
    to ~/practice/inventory/reorder-${DATE}.txt"

    apex "use espeak to say supply reorder list generated for ${DATE}"
}

# ── EOD SUMMARY ───────────────────────────────────────────
end_of_day() {
    apex "read ~/practice/schedule/appointments-${DATE}.txt \
    ~/practice/billing/billing-log.txt \
    and write an end of day operational summary for ${DATE} \
    covering total appointments seen no-shows \
    billing entries logged and any supply issues \
    using anonymized data only \
    to ~/practice/reports/eod-${DATE}.txt"

    apex "read ~/practice/reports/eod-${DATE}.txt \
    and use espeak in a calm professional voice at speed 135 \
    and save to ~/practice/audio/eod-${DATE}.wav"

    aplay ~/practice/audio/eod-${DATE}.wav 2>/dev/null
}

# ── NIGHTLY COMPLIANCE AUDIT ──────────────────────────────
compliance_audit() {
    apex "write a compliance audit log entry for ${DATE} \
    recording system access events file modifications \
    and data handling activities from today's logs \
    to ~/practice/compliance/audit-${DATE}.txt"

    apex "check that all files in ~/practice/patients \
    follow the anonymized ID naming convention \
    and write any violations to ~/practice/compliance/violations-${DATE}.txt"

    apex "append audit complete ${DATE} to ~/practice/compliance/audit-index.txt"
}

# ── WEEKLY REVIEW ─────────────────────────────────────────
weekly_review() {
    apex "read all schedule and eod files from this week \
    in ~/practice/reports \
    and calculate total appointments no-show rate \
    busiest days and peak appointment types \
    to ~/practice/reports/weekly-ops-${DATE}.txt" &

    apex "read ~/practice/billing/billing-log.txt \
    and calculate weekly revenue collected \
    insurance claims submitted and outstanding \
    to ~/practice/reports/weekly-billing-${DATE}.txt" &

    wait

    apex "read ~/practice/reports/weekly-ops-${DATE}.txt \
    ~/practice/reports/weekly-billing-${DATE}.txt \
    and write a comprehensive weekly practice review for week ${WEEK} \
    covering operational efficiency billing health and supply status \
    using anonymized data throughout \
    to ~/practice/reports/weekly-review-${DATE}.txt"

    apex "read ~/practice/reports/weekly-review-${DATE}.txt \
    and use espeak in a professional voice at speed 135 \
    and save to ~/practice/audio/weekly-review-${DATE}.wav"

    aplay ~/practice/audio/weekly-review-${DATE}.wav 2>/dev/null
}

# ── MONTHLY REPORT ────────────────────────────────────────
monthly_report() {
    apex "read all weekly reports in ~/practice/reports \
    and generate a full monthly operational and financial report \
    for ${MONTH} covering patient volumes revenue collected \
    insurance claim status compliance summary and supply costs \
    using anonymized data throughout \
    to ~/practice/reports/monthly-${MONTH}.txt"

    apex "read ~/practice/reports/monthly-${MONTH}.txt \
    and use espeak in a confident clinical administrator voice at speed 140 \
    and save to ~/practice/audio/monthly-${MONTH}.wav"

    aplay ~/practice/audio/monthly-${MONTH}.wav 2>/dev/null
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)        morning_brief ;;
    midday)         midday_brief ;;
    recall)         generate_recall_letters "$@" ;;
    billing)        log_billing "$@" ;;
    reorder)        reorder_supplies ;;
    eod)            end_of_day ;;
    compliance)     compliance_audit ;;
    weekly)         weekly_review ;;
    monthly)        monthly_report ;;
    *)              echo "Unknown: $CMD" ;;
esac
