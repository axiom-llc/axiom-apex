#!/usr/bin/env bash
# ============================================================
# healthcare-rcm.sh — Revenue cycle management automation
# Requires: apex
# Config:   PAYER_FILE  — one payer name per line
#           PROVIDER    — your practice/org name
# Cron:     0 7  * * 1-5  ./healthcare-rcm.sh morning
#           0 12 * * 1-5  ./healthcare-rcm.sh ar-sweep
#           0 17 * * 1-5  ./healthcare-rcm.sh eod
#           0 6  * * 1    ./healthcare-rcm.sh weekly
# ============================================================
set -euo pipefail

PROVIDER="${PROVIDER:-$(cat ~/.config/apex/rcm_provider 2>/dev/null || echo "Your Practice Name")}"
PAYER_FILE="${PAYER_FILE:-${HOME}/.config/apex/rcm_payers}"
DATE=$(date +%Y-%m-%d)
WEEK=$(date +%V)
MONTH=$(date +%B_%Y)

mkdir -p ~/rcm/{claims,denials,ar,auth,reports,alerts,logs,archives}

CMD=${1:-morning}

# ── MORNING BRIEF ─────────────────────────────────────────
morning() {
    echo "[${DATE}] Morning RCM brief..." >> ~/rcm/logs/rcm.log

    # Parallel: AR aging + denial queue + auth expirations
    apex "read ~/rcm/ar/ar-ledger.txt using read_file
    calculate accounts receivable aging buckets: current 30 60 90 120+ days
    flag any accounts over 90 days for immediate action
    write AR aging summary to ~/rcm/ar/aging-${DATE}.txt" &

    apex "read ~/rcm/denials/denial-queue.txt using read_file
    identify all unworked denials older than 7 days
    group by denial reason code
    flag any approaching timely filing deadlines
    write denial work queue to ~/rcm/denials/queue-${DATE}.txt" &

    apex "read ~/rcm/auth/auth-log.txt using read_file
    identify prior authorizations expiring within 7 days
    write expiration alerts to ~/rcm/auth/expiring-${DATE}.txt" &

    wait

    apex "read ~/rcm/ar/aging-${DATE}.txt
    ~/rcm/denials/queue-${DATE}.txt
    ~/rcm/auth/expiring-${DATE}.txt using read_file
    write a structured morning RCM brief for ${PROVIDER} on ${DATE} with sections:
    AR AGING SNAPSHOT | DENIAL WORK QUEUE | AUTH EXPIRATIONS | PRIORITY ACTIONS TODAY
    write to ~/rcm/reports/morning-${DATE}.txt"

    cat ~/rcm/reports/morning-${DATE}.txt
    echo "[${DATE}] Morning brief complete." >> ~/rcm/logs/rcm.log
}

# ── CLAIM INTAKE + SCRUB ──────────────────────────────────
scrub_claim() {
    CLAIM_FILE="$2"
    [[ ! -f "$CLAIM_FILE" ]] && echo "✗ Claim file not found: $CLAIM_FILE" && exit 1

    apex "read the claim file at ${CLAIM_FILE} using read_file
    perform pre-submission claim scrub:
    - Validate ICD-10 and CPT code combinations for medical necessity
    - Check for missing or invalid modifiers
    - Verify NPI, taxonomy, and place of service codes
    - Flag any NCCI edits or bundling issues
    - Check patient demographic completeness
    output: CLEAN (ready to submit) or ERRORS with specific line-item corrections
    write scrub report to ~/rcm/claims/scrub-$(basename ${CLAIM_FILE})-${DATE}.txt"

    cat ~/rcm/claims/scrub-$(basename ${CLAIM_FILE})-${DATE}.txt
}

# ── DENIAL ANALYSIS + APPEAL ──────────────────────────────
work_denial() {
    DENIAL_FILE="$2"
    [[ ! -f "$DENIAL_FILE" ]] && echo "✗ Denial file not found: $DENIAL_FILE" && exit 1

    apex "read the denial at ${DENIAL_FILE} using read_file
    analyse the denial:
    - Identify the CARC/RARC reason codes
    - Determine root cause: clinical, administrative, or eligibility
    - Assess appeal viability and success probability
    - Draft a first-level appeal letter if viable
    - Recommend: APPEAL | CORRECT AND RESUBMIT | WRITE OFF | ESCALATE
    write analysis and appeal draft to ~/rcm/denials/worked-$(basename ${DENIAL_FILE})-${DATE}.txt"

    cat ~/rcm/denials/worked-$(basename ${DENIAL_FILE})-${DATE}.txt
}

# ── AR SWEEP — PARALLEL PAYER FOLLOW-UP ──────────────────
ar_sweep() {
    echo "[${DATE}] AR sweep..." >> ~/rcm/logs/rcm.log
    [[ ! -f "$PAYER_FILE" ]] && echo "✗ Payer file not found: $PAYER_FILE" && exit 1

    PIDS=()
    while IFS= read -r payer; do
        [[ -z "$payer" ]] && continue
        slug=$(echo "$payer" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
        (
            apex "read ~/rcm/ar/ar-ledger.txt using read_file
            extract all open claims for payer: ${payer}
            identify claims over 45 days without payment or response
            draft follow-up talking points for each: claim number amount date of service
            write to ~/rcm/ar/followup-${slug}-${DATE}.txt"
        ) &
        PIDS+=($!)
    done < "$PAYER_FILE"

    for pid in "${PIDS[@]}"; do wait "$pid" || true; done

    apex "read all followup files created today in ~/rcm/ar using read_file
    write consolidated AR follow-up action list prioritised by dollar amount
    to ~/rcm/ar/ar-actions-${DATE}.txt"

    cat ~/rcm/ar/ar-actions-${DATE}.txt
    echo "[${DATE}] AR sweep complete." >> ~/rcm/logs/rcm.log
}

# ── END OF DAY RECONCILIATION ─────────────────────────────
eod() {
    apex "read all claim activity in ~/rcm/claims from today
    and ~/rcm/denials/denial-queue.txt
    and ~/rcm/ar/ar-ledger.txt using read_file
    write an end-of-day RCM summary for ${PROVIDER} on ${DATE}:
    CLAIMS SUBMITTED | PAYMENTS POSTED | DENIALS RECEIVED | DENIALS WORKED |
    NET COLLECTIONS | OUTSTANDING AR | ITEMS REQUIRING ACTION TOMORROW
    write to ~/rcm/reports/eod-${DATE}.txt"

    cat ~/rcm/reports/eod-${DATE}.txt
    echo "[${DATE}] EOD complete." >> ~/rcm/logs/rcm.log
}

# ── WEEKLY PERFORMANCE REPORT ─────────────────────────────
weekly() {
    apex "read all reports in ~/rcm/reports from this week using read_file
    write a weekly RCM performance report for ${PROVIDER} week ${WEEK} with:
    CLEAN CLAIM RATE | FIRST-PASS RESOLUTION RATE | DENIAL RATE BY PAYER |
    DAYS IN AR | COLLECTION RATE | WEEK-OVER-WEEK TREND |
    TOP 3 DENIAL REASON CODES | RECOMMENDED PROCESS IMPROVEMENTS
    write to ~/rcm/reports/weekly-${WEEK}-${DATE}.txt"

    cat ~/rcm/reports/weekly-${WEEK}-${DATE}.txt
    echo "[${DATE}] Weekly report complete." >> ~/rcm/logs/rcm.log
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)      morning ;;
    scrub)        scrub_claim "$@" ;;
    denial)       work_denial "$@" ;;
    ar-sweep)     ar_sweep ;;
    eod)          eod ;;
    weekly)       weekly ;;
    *)            echo "Commands: morning | scrub <file> | denial <file> | ar-sweep | eod | weekly" ;;
esac
