#!/usr/bin/env bash
# ============================================================
# insurance-claims.sh — Claims processing and adjudication
# Requires: apex
# Config:   LINES_OF_BUSINESS — comma-separated (auto,property,liability)
#           ADJUSTER_LOAD     — max open claims per adjuster
# Cron:     0 7  * * 1-5  ./insurance-claims.sh morning
#           0 8  * * 1-5  ./insurance-claims.sh triage-new
#           0 15 * * 1-5  ./insurance-claims.sh status-sweep
#           0 6  * * 1    ./insurance-claims.sh weekly
# ============================================================
set -euo pipefail

ORG="${ORG:-$(cat ~/.config/apex/claims_org 2>/dev/null || echo "Your Organization")}"
DATE=$(date +%Y-%m-%d)
WEEK=$(date +%V)

mkdir -p ~/claims/{intake,triage,investigation,settlements,reports,flags,logs,archives}

CMD=${1:-morning}

# ── MORNING BRIEF ─────────────────────────────────────────
morning() {
    # Parallel: new intake + pending investigations + settlement queue
    apex "read ~/claims/intake/new-claims.txt using read_file
    count new claims received since yesterday
    flag any catastrophic loss indicators (fire total loss structural collapse fatality)
    write intake summary to ~/claims/reports/intake-summary-${DATE}.txt" &

    apex "read ~/claims/investigation/open-investigations.txt using read_file
    identify investigations with no activity in 5+ days
    flag any approaching state-mandated response deadlines
    write stalled investigation alerts to ~/claims/flags/stalled-${DATE}.txt" &

    apex "read ~/claims/settlements/pending-settlements.txt using read_file
    calculate total reserve exposure
    flag any settlements pending approval over 30 days
    write settlement queue to ~/claims/reports/settlement-queue-${DATE}.txt" &

    wait

    apex "read ~/claims/reports/intake-summary-${DATE}.txt
    ~/claims/flags/stalled-${DATE}.txt
    ~/claims/reports/settlement-queue-${DATE}.txt using read_file
    write structured morning claims brief for ${ORG} on ${DATE}:
    NEW CLAIMS | STALLED INVESTIGATIONS | PENDING SETTLEMENTS |
    CATASTROPHIC FLAGS | COMPLIANCE DEADLINES | PRIORITY ACTIONS
    write to ~/claims/reports/morning-${DATE}.txt"

    cat ~/claims/reports/morning-${DATE}.txt
}

# ── CLAIM INTAKE + TRIAGE ─────────────────────────────────
triage_claim() {
    CLAIM_FILE="$2"
    [[ ! -f "$CLAIM_FILE" ]] && echo "✗ Claim file not found: $CLAIM_FILE" && exit 1
    CLAIM_ID="CLM-$(date +%s)"

    apex "read the claim submission at ${CLAIM_FILE} using read_file
    perform initial triage:
    COVERAGE VERIFICATION: does the reported loss appear to fall within policy terms?
    SEVERITY CLASSIFICATION: CAT (catastrophic) | COMPLEX | STANDARD | FAST-TRACK
    FRAUD INDICATORS: flag any red flags from the 10 most common fraud patterns
    INVESTIGATION SCOPE: what evidence, inspections, or statements are required?
    RESERVE ESTIMATE: initial reserve range based on reported facts
    ASSIGNMENT RECOMMENDATION: which adjuster tier should handle this?
    write triage report to ~/claims/triage/${CLAIM_ID}-triage-${DATE}.txt"

    apex "append ${CLAIM_ID} $(date +%H:%M) triaged to ~/claims/intake/claim-log.txt"
    cat ~/claims/triage/${CLAIM_ID}-triage-${DATE}.txt
}

# ── PARALLEL TRIAGE — ALL NEW CLAIMS ─────────────────────
triage_new() {
    NEW=$(find ~/claims/intake/new/ -name "*.txt" 2>/dev/null | head -20)
    [[ -z "$NEW" ]] && echo "No new claims in ~/claims/intake/new/" && exit 0

    PIDS=()
    while IFS= read -r claim_file; do
        (bash "$0" triage "$claim_file") &
        PIDS+=($!)
    done <<< "$NEW"

    for pid in "${PIDS[@]}"; do wait "$pid" || true; done

    apex "read all triage reports created today in ~/claims/triage using read_file
    write a triage batch summary: total triaged by severity tier fraud flags raised
    reserve exposure total to ~/claims/reports/triage-batch-${DATE}.txt"

    cat ~/claims/reports/triage-batch-${DATE}.txt
}

# ── FRAUD SCREENING ───────────────────────────────────────
fraud_screen() {
    CLAIM_FILE="$2"
    [[ ! -f "$CLAIM_FILE" ]] && echo "✗ Not found: $CLAIM_FILE" && exit 1

    apex "read the claim at ${CLAIM_FILE} using read_file
    perform structured fraud screening against these patterns:
    - Staged accident indicators (multiple claimants single vehicle, attorney represented day-of)
    - Soft tissue only with no property damage
    - Loss reported significantly after incident date
    - Claimant history of prior claims (check claim-log.txt)
    - Inconsistencies between recorded statement and police/fire report
    - Medical treatment pattern inconsistent with mechanism of injury
    - Provider billing pattern anomalies
    - Social media activity contradicting claimed injuries
    output: CLEAR | SUSPICIOUS | REFER TO SIU with specific indicators
    write to ~/claims/flags/fraud-screen-$(basename ${CLAIM_FILE})-${DATE}.txt"

    cat ~/claims/flags/fraud-screen-$(basename ${CLAIM_FILE})-${DATE}.txt
}

# ── SETTLEMENT EVALUATION ─────────────────────────────────
evaluate_settlement() {
    CLAIM_FILE="$2"
    [[ ! -f "$CLAIM_FILE" ]] && echo "✗ Not found: $CLAIM_FILE" && exit 1

    apex "read the claim file at ${CLAIM_FILE} using read_file
    produce a settlement evaluation:
    SPECIAL DAMAGES: itemised medical bills lost wages out-of-pocket
    GENERAL DAMAGES: pain and suffering range based on injury type and jurisdiction
    COMPARATIVE FAULT: any claimant negligence that reduces exposure
    COVERAGE LIMITS: applicable policy limits and SIR/deductible
    RECOMMENDED RANGE: low | midpoint | high with rationale for each
    SETTLEMENT AUTHORITY: does this require supervisor approval?
    write to ~/claims/settlements/eval-$(basename ${CLAIM_FILE})-${DATE}.txt"

    cat ~/claims/settlements/eval-$(basename ${CLAIM_FILE})-${DATE}.txt
}

# ── STATUS SWEEP ──────────────────────────────────────────
status_sweep() {
    apex "read ~/claims/investigation/open-investigations.txt using read_file
    for each open claim assess current status against state-mandated timelines:
    acknowledgement (3 days) | coverage decision (15 days) | payment (30 days)
    flag any claims approaching or past deadline
    write compliance status report to ~/claims/reports/compliance-${DATE}.txt"

    cat ~/claims/reports/compliance-${DATE}.txt
}

# ── WEEKLY REPORT ─────────────────────────────────────────
weekly() {
    apex "read all reports in ~/claims/reports from this week using read_file
    write weekly claims operations report for week ${WEEK}:
    VOLUME: new claims opened closed pending by line of business
    FINANCIALS: reserves set payments made salvage recovered subrogation identified
    QUALITY: average cycle time denial rate litigation rate SIU referrals
    COMPLIANCE: any deadline misses or regulatory exposure
    TRENDS: week-over-week changes and emerging patterns
    write to ~/claims/reports/weekly-${WEEK}-${DATE}.txt"

    cat ~/claims/reports/weekly-${WEEK}-${DATE}.txt
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)       morning ;;
    triage)        triage_claim "$@" ;;
    triage-new)    triage_new ;;
    fraud)         fraud_screen "$@" ;;
    settle)        evaluate_settlement "$@" ;;
    status-sweep)  status_sweep ;;
    weekly)        weekly ;;
    *)             echo "Commands: morning | triage <file> | triage-new | fraud <file> | settle <file> | status-sweep | weekly" ;;
esac
