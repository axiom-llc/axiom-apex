#!/usr/bin/env bash
# ============================================================
# law-firm.sh — Solo and small firm practice automation
# Covers: matter intake, time entry, deadline tracking,
# client communication, billing, and conflict checking
# Requires: apex
# Config:   ~/.config/apex/firm_name       — firm name
#           ~/.config/apex/practice_areas  — comma-separated
#           ~/.config/apex/billing_rate    — default hourly rate
# Cron:     0 7  * * 1-5  ./law-firm.sh morning
#           0 17 * * 1-5  ./law-firm.sh eod
#           0 8  * * 1    ./law-firm.sh weekly
#           0 9  1 * *    ./law-firm.sh invoice-all
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

FIRM="${FIRM:-$(cat ~/.config/apex/firm_name 2>/dev/null || echo "Your Law Firm")}"
PRACTICE_AREAS=$(cat ~/.config/apex/practice_areas 2>/dev/null || echo "contracts, employment, business formation")
RATE="${BILLING_RATE:-$(cat ~/.config/apex/billing_rate 2>/dev/null || echo "350")}"
DATE=$(date +%Y-%m-%d)
WEEK=$(date +%V)
MONTH=$(date +%B_%Y)

mkdir -p ~/lawfirm/{matters,clients,timesheets,invoices,deadlines,conflicts,reports,comms,logs}

CMD=${1:-morning}

# ── MORNING BRIEF ─────────────────────────────────────────
morning() {
    echo "[${DATE}] Morning brief..." >> ~/lawfirm/logs/firm.log

    # Parallel: deadlines + unbilled time + client follow-ups
    apex "read ~/lawfirm/deadlines/deadline-register.txt using read_file
    identify all deadlines within the next 14 days
    flag CRITICAL: court dates, filing deadlines, statute of limitations
    flag WARNING: client deliverables, response deadlines
    sort chronologically
    write to ~/lawfirm/reports/deadlines-${DATE}.txt" &

    apex "read all timesheet files in ~/lawfirm/timesheets using read_file
    identify matters with unbilled time older than 30 days
    calculate total unbilled value at ${RATE}/hr
    write unbilled summary to ~/lawfirm/reports/unbilled-${DATE}.txt" &

    apex "read ~/lawfirm/clients/client-register.txt using read_file
    identify clients with no attorney contact in 14+ days on active matters
    write client touch-base list to ~/lawfirm/reports/touchbase-${DATE}.txt" &

    wait

    apex "read ~/lawfirm/reports/deadlines-${DATE}.txt
    ~/lawfirm/reports/unbilled-${DATE}.txt
    ~/lawfirm/reports/touchbase-${DATE}.txt using read_file
    write structured morning brief for ${FIRM} on ${DATE}:
    CRITICAL DEADLINES | UPCOMING DEADLINES | UNBILLED TIME |
    CLIENT TOUCH-BASES DUE | PRIORITY ACTIONS TODAY
    write to ~/lawfirm/reports/morning-${DATE}.txt"

    cat ~/lawfirm/reports/morning-${DATE}.txt
    echo "[${DATE}] Morning brief complete." >> ~/lawfirm/logs/firm.log
}

# ── MATTER INTAKE + CONFLICT CHECK ────────────────────────
intake() {
    INTAKE_FILE="$2"
    [[ ! -f "$INTAKE_FILE" ]] && echo "✗ Intake file not found: $INTAKE_FILE" && exit 1
    MATTER_ID="MTR-$(date +%s)"

    # Conflict check runs first — non-negotiable
    apex "read the new matter intake at ${INTAKE_FILE} using read_file
    read ~/lawfirm/clients/client-register.txt
    ~/lawfirm/matters/matter-register.txt using read_file
    perform a conflict of interest check:
    - Direct conflicts: is any party an existing or former client?
    - Positional conflicts: would this matter oppose a position taken in another matter?
    - Business conflicts: any financial interest in the outcome?
    output: CLEAR | CONFLICT_DETECTED | NEEDS_REVIEW
    if CONFLICT_DETECTED: specify the conflicting matter and parties
    write conflict check to ~/lawfirm/conflicts/${MATTER_ID}-conflict-${DATE}.txt"

    CONFLICT=$(grep -oE "^(CLEAR|CONFLICT_DETECTED|NEEDS_REVIEW)" \
        ~/lawfirm/conflicts/${MATTER_ID}-conflict-${DATE}.txt 2>/dev/null | head -1 || echo "NEEDS_REVIEW")

    if [[ "$CONFLICT" == "CONFLICT_DETECTED" ]]; then
        echo "⚠ CONFLICT DETECTED — matter ${MATTER_ID} cannot proceed without review"
        cat ~/lawfirm/conflicts/${MATTER_ID}-conflict-${DATE}.txt
        echo "[${DATE}] Matter ${MATTER_ID} blocked on conflict." >> ~/lawfirm/logs/firm.log
        exit 1
    fi

    # Intake proceeds only if clear
    apex "read the intake at ${INTAKE_FILE} using read_file
    create a new matter file for ${MATTER_ID}:
    extract: client name, opposing parties, matter type, key facts, immediate deadlines
    assess: complexity (straightforward|moderate|complex), estimated hours, fee arrangement
    recommend: retainer amount based on complexity at ${RATE}/hr
    write matter file to ~/lawfirm/matters/${MATTER_ID}-${DATE}.txt"

    apex "append ${MATTER_ID} ${DATE} OPEN \
    to ~/lawfirm/matters/matter-register.txt"

    # Engagement letter
    apex "read ~/lawfirm/matters/${MATTER_ID}-${DATE}.txt using read_file
    draft a professional engagement letter from ${FIRM}:
    scope of representation, fee arrangement, retainer amount,
    billing frequency, client obligations, termination provisions
    keep under 400 words — clear not exhaustive
    write to ~/lawfirm/comms/${MATTER_ID}-engagement-${DATE}.txt"

    cat ~/lawfirm/comms/${MATTER_ID}-engagement-${DATE}.txt
    echo "[${DATE}] Matter ${MATTER_ID} opened. Conflict: ${CONFLICT}" >> ~/lawfirm/logs/firm.log
}

# ── TIME ENTRY ────────────────────────────────────────────
time_entry() {
    MATTER_ID="$2"
    HOURS="$3"
    DESCRIPTION="$4"
    BILLING_CODE="${5:-general}"

    apex "append time entry: ${DATE} ${HOURS}hrs [${BILLING_CODE}] ${DESCRIPTION} \
    to ~/lawfirm/timesheets/${MATTER_ID}-timesheet.txt"

    # Running ledger
    apex "read ~/lawfirm/timesheets/${MATTER_ID}-timesheet.txt using read_file
    calculate total hours and fees accrued at ${RATE}/hr
    write running total to ~/lawfirm/timesheets/${MATTER_ID}-total.txt"

    echo "   ✓ ${HOURS}hrs logged to ${MATTER_ID}: ${DESCRIPTION}"
}

# ── DEADLINE REGISTRATION ─────────────────────────────────
add_deadline() {
    MATTER_ID="$2"
    DEADLINE_DATE="$3"
    DESCRIPTION="$4"
    SEVERITY="${5:-WARNING}"

    apex "append deadline: ${MATTER_ID} ${DEADLINE_DATE} ${SEVERITY} ${DESCRIPTION} \
    to ~/lawfirm/deadlines/deadline-register.txt"

    # Check if deadline is within 7 days
    DAYS_OUT=$(( ($(date -d "$DEADLINE_DATE" +%s) - $(date +%s)) / 86400 ))
    if [[ $DAYS_OUT -le 7 ]]; then
        echo "⚠ Deadline in ${DAYS_OUT} days: ${DESCRIPTION}"
    fi

    echo "   ✓ Deadline registered: ${DEADLINE_DATE} — ${DESCRIPTION}"
}

# ── CLIENT STATUS UPDATE ──────────────────────────────────
status_update() {
    MATTER_ID="$2"
    [[ -z "$MATTER_ID" ]] && echo "Usage: $0 status <matter-id>" && exit 1

    apex "read ~/lawfirm/matters/${MATTER_ID}-*.txt
    ~/lawfirm/timesheets/${MATTER_ID}-timesheet.txt using read_file
    write a professional client status update email:
    - Current status of the matter in plain language
    - What has been done since last update
    - Next steps and expected timeline
    - Any action required from the client
    - Hours and fees to date (unbilled)
    tone: clear, reassuring, no legalese
    under 250 words
    write to ~/lawfirm/comms/${MATTER_ID}-status-${DATE}.txt"

    cat ~/lawfirm/comms/${MATTER_ID}-status-${DATE}.txt
}

# ── INVOICE GENERATION ────────────────────────────────────
invoice() {
    MATTER_ID="$2"
    [[ -z "$MATTER_ID" ]] && echo "Usage: $0 invoice <matter-id>" && exit 1
    INVOICE_ID="INV-${MATTER_ID}-$(date +%Y%m)"

    apex "read ~/lawfirm/matters/${MATTER_ID}-*.txt
    ~/lawfirm/timesheets/${MATTER_ID}-timesheet.txt using read_file
    write a professional legal invoice ${INVOICE_ID} from ${FIRM}:
    client name and address from matter file
    itemised time entries with date description hours rate and amount
    disbursements if any
    subtotal, applicable tax, total due
    payment terms: due on receipt
    trust account instructions if retainer held
    write to ~/lawfirm/invoices/${INVOICE_ID}-${DATE}.txt"

    apex "append ${INVOICE_ID} ${MATTER_ID} $(date +%Y%m) UNPAID ${DATE} \
    to ~/lawfirm/invoices/invoice-ledger.txt"

    cat ~/lawfirm/invoices/${INVOICE_ID}-${DATE}.txt
    echo "[${DATE}] Invoice ${INVOICE_ID} generated." >> ~/lawfirm/logs/firm.log
}

# ── INVOICE ALL ACTIVE MATTERS ────────────────────────────
invoice_all() {
    while IFS= read -r line; do
        MATTER_ID=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $3}')
        [[ "$STATUS" != "OPEN" ]] && continue
        [[ -z "$MATTER_ID" ]] && continue
        invoice "$CMD" "$MATTER_ID" &
    done < ~/lawfirm/matters/matter-register.txt 2>/dev/null || true

    wait

    apex "read ~/lawfirm/invoices/invoice-ledger.txt using read_file
    calculate total invoiced this month total outstanding total collected
    write billing summary to ~/lawfirm/reports/billing-${MONTH}.txt"

    cat ~/lawfirm/reports/billing-${MONTH}.txt
}

# ── EOD WRAP ──────────────────────────────────────────────
eod() {
    apex "read all today's activity in ~/lawfirm using read_file:
    matters opened, time entries logged, deadlines added, invoices generated

    write end-of-day summary for ${FIRM} on ${DATE}:
    TIME LOGGED TODAY | MATTERS ACTIVE | DEADLINES THIS WEEK |
    INVOICES OUTSTANDING | TOMORROW'S PRIORITIES
    write to ~/lawfirm/reports/eod-${DATE}.txt"

    cat ~/lawfirm/reports/eod-${DATE}.txt
    echo "[${DATE}] EOD complete." >> ~/lawfirm/logs/firm.log
}

# ── WEEKLY REVIEW ─────────────────────────────────────────
weekly() {
    apex "read all reports and matter files from this week in ~/lawfirm using read_file
    write weekly practice review for ${FIRM} week ${WEEK}:
    BILLINGS: hours recorded fees billed collected outstanding
    MATTER ACTIVITY: opened closed active by practice area
    DEADLINE COMPLIANCE: upcoming critical dates missed deadlines
    CLIENT HEALTH: matters with no recent activity
    UTILISATION: billable hours this week vs prior week
    write to ~/lawfirm/reports/weekly-${WEEK}-${DATE}.txt"

    cat ~/lawfirm/reports/weekly-${WEEK}-${DATE}.txt
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)     morning ;;
    intake)      intake "$@" ;;
    time)        time_entry "$@" ;;
    deadline)    add_deadline "$@" ;;
    status)      status_update "$@" ;;
    invoice)     invoice "$@" ;;
    invoice-all) invoice_all ;;
    eod)         eod ;;
    weekly)      weekly ;;
    *)           echo "Commands: morning | intake <file> | time <matter> <hours> <desc> | deadline <matter> <date> <desc> | status <matter> | invoice <matter> | invoice-all | eod | weekly" ;;
esac
