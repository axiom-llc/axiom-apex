#!/usr/bin/env bash
# ============================================================
# compliance-audit.sh — Automated regulatory compliance audit
# Supports: SOC 2, HIPAA, PCI-DSS, GDPR, ISO 27001
# Requires: apex
# Config:   FRAMEWORKS — space-separated list of applicable frameworks
#           ORG_NAME   — your organization name
# Cron:     0 2  * * *   ./compliance-audit.sh nightly
#           0 7  * * 1   ./compliance-audit.sh weekly
#           0 6  1 * *   ./compliance-audit.sh monthly
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

ORG="${ORG_NAME:-$(cat ~/.config/apex/compliance_org 2>/dev/null || echo "Your Organization")}"
FRAMEWORKS="${FRAMEWORKS:-SOC2 HIPAA}"
DATE=$(date +%Y-%m-%d)
MONTH=$(date +%B_%Y)
WEEK=$(date +%V)

mkdir -p ~/compliance/{evidence,findings,controls,reports,remediation,logs}

CMD=${1:-nightly}

# ── NIGHTLY CONTROL CHECK ─────────────────────────────────
nightly() {
    echo "[${DATE}] Nightly compliance sweep..." >> ~/compliance/logs/audit.log

    # Parallel control checks per framework
    PIDS=()
    for framework in $FRAMEWORKS; do
        (
            apex "perform a compliance control spot-check for ${ORG} against ${framework} on ${DATE}

            Check the following control categories using shell commands where possible:
            ACCESS CONTROLS: review sudo logs, SSH auth logs, failed login attempts in last 24h
            DATA HANDLING: check for world-readable sensitive files, unencrypted data at rest indicators
            AUDIT LOGGING: verify log rotation is current, no gaps in audit trail
            PATCH STATUS: check for packages with pending security updates
            NETWORK CONTROLS: verify firewall rules have not changed from baseline

            For each control: PASS | FAIL | WARNING with specific evidence
            Write findings to ~/compliance/findings/${framework}-nightly-${DATE}.txt"
        ) &
        PIDS+=($!)
    done

    for pid in "${PIDS[@]}"; do wait "$pid" || true; done

    # Aggregate and alert on failures
    apex "read all nightly findings files created today in ~/compliance/findings using read_file
    aggregate all FAIL and WARNING findings across all frameworks
    write consolidated alert report to ~/compliance/reports/nightly-alerts-${DATE}.txt
    if any FAIL findings exist flag as CRITICAL"

    # Only output if issues found
    if grep -q "FAIL\|CRITICAL" ~/compliance/reports/nightly-alerts-${DATE}.txt 2>/dev/null; then
        cat ~/compliance/reports/nightly-alerts-${DATE}.txt
    else
        echo "   ✓ All controls passing — $(date)"
    fi

    echo "[${DATE}] Nightly sweep complete." >> ~/compliance/logs/audit.log
}

# ── FULL FRAMEWORK AUDIT ──────────────────────────────────
audit_framework() {
    FRAMEWORK="${2:-SOC2}"
    echo "[${DATE}] Full ${FRAMEWORK} audit..." >> ~/compliance/logs/audit.log

    # Map frameworks to their control domains
    declare -A DOMAINS
    DOMAINS[SOC2]="CC1:Control_Environment CC2:Communication CC3:Risk_Assessment CC6:Logical_Access CC7:System_Operations CC8:Change_Management CC9:Risk_Mitigation"
    DOMAINS[HIPAA]="164.308:Administrative 164.310:Physical 164.312:Technical 164.314:Organizational 164.316:Policies"
    DOMAINS[PCI_DSS]="Req1:Network_Security Req2:Secure_Config Req3:Cardholder_Data Req4:Encryption Req6:Secure_Systems Req7:Access_Control Req10:Logging Req11:Testing"
    DOMAINS[GDPR]="Art5:Principles Art6:Lawfulness Art13:Transparency Art25:DataByDesign Art32:Security Art33:BreachNotification Art35:DPIA"

    DOMAIN_LIST="${DOMAINS[$FRAMEWORK]:-General:Controls}"

    # Parallel audit per domain
    PIDS=()
    for domain_pair in $DOMAIN_LIST; do
        domain_id="${domain_pair%%:*}"
        domain_name="${domain_pair##*:}"
        (
            apex "conduct a ${FRAMEWORK} compliance audit for control domain ${domain_id}: ${domain_name}
            Organization: ${ORG}

            For each control in this domain:
            1. State the control requirement
            2. Assess current implementation: IMPLEMENTED | PARTIAL | NOT_IMPLEMENTED | NOT_APPLICABLE
            3. Identify evidence that should exist to demonstrate compliance
            4. Note any gaps or deficiencies
            5. Assign risk rating: HIGH | MEDIUM | LOW

            Write structured findings to ~/compliance/findings/${FRAMEWORK}-${domain_id}-${DATE}.txt"
        ) &
        PIDS+=($!)
    done

    for pid in "${PIDS[@]}"; do wait "$pid" || true; done

    # Synthesis report
    apex "read all ${FRAMEWORK} findings files from today in ~/compliance/findings using read_file

    Write a comprehensive ${FRAMEWORK} compliance audit report for ${ORG} dated ${DATE}:

    EXECUTIVE SUMMARY: overall compliance posture, critical gaps, audit opinion
    SCOPE AND METHODOLOGY: what was assessed and how
    FINDINGS BY CONTROL DOMAIN: implementation status, gaps, evidence requirements
    RISK REGISTER: all HIGH and MEDIUM findings with risk rating and owner
    REMEDIATION ROADMAP: prioritised action plan with estimated effort
    MANAGEMENT RESPONSE TEMPLATE: pre-formatted response sections for each finding

    Write to ~/compliance/reports/${FRAMEWORK}-audit-${DATE}.txt"

    cat ~/compliance/reports/${FRAMEWORK}-audit-${DATE}.txt
    echo "[${DATE}] ${FRAMEWORK} audit complete." >> ~/compliance/logs/audit.log
}

# ── EVIDENCE COLLECTION ───────────────────────────────────
collect_evidence() {
    CONTROL="$2"
    [[ -z "$CONTROL" ]] && echo "Usage: $0 evidence \"control description\"" && exit 1

    apex "collect compliance evidence for control: ${CONTROL}

    Use shell to gather:
    - Relevant log entries (auth.log, syslog, audit.log)
    - Configuration file snapshots
    - Access control listings
    - System state indicators

    Format findings as audit-ready evidence:
    CONTROL: what is being tested
    EVIDENCE COLLECTED: specific data gathered with timestamps
    RESULT: SATISFACTORY | UNSATISFACTORY | INCONCLUSIVE
    EVIDENCE FILE: write raw evidence to ~/compliance/evidence/$(echo ${CONTROL} | tr ' ' '_')-${DATE}.txt

    Write evidence summary to ~/compliance/evidence/summary-${DATE}.txt"

    cat ~/compliance/evidence/summary-${DATE}.txt
}

# ── REMEDIATION TRACKING ──────────────────────────────────
remediation_status() {
    apex "read ~/compliance/remediation/remediation-log.txt using read_file
    assess status of all open remediation items:
    - Items overdue (past target date)
    - Items due within 7 days
    - Items completed since last check
    - Overall remediation velocity trend
    write status report to ~/compliance/reports/remediation-status-${DATE}.txt"

    cat ~/compliance/reports/remediation-status-${DATE}.txt
}

# ── WEEKLY POSTURE REPORT ─────────────────────────────────
weekly() {
    apex "read all findings and reports from this week in ~/compliance using read_file
    write a weekly compliance posture report for ${ORG} week ${WEEK}:
    CONTROL PASS RATE: percentage of controls passing across all frameworks
    NEW FINDINGS: issues identified this week not present last week
    RESOLVED FINDINGS: issues closed this week
    OPEN HIGH RISK ITEMS: count and age of unresolved high-risk findings
    FRAMEWORK COVERAGE: audit completeness per framework
    TREND: improving | stable | degrading with rationale
    write to ~/compliance/reports/weekly-${WEEK}-${DATE}.txt"

    cat ~/compliance/reports/weekly-${WEEK}-${DATE}.txt
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    nightly)     nightly ;;
    audit)       audit_framework "$@" ;;
    evidence)    collect_evidence "$@" ;;
    remediation) remediation_status ;;
    weekly)      weekly ;;
    *)           echo "Commands: nightly | audit <framework> | evidence <control> | remediation | weekly" ;;
esac
