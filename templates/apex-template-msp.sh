#!/bin/bash
# ============================================================
# APEX INTEGRATION TEMPLATE — IT MSP / MANAGED SERVICES
# Version: 1.0
# Author: [Your Name] — Independent IT Consultant
# Client: [Your MSP Name]
# ============================================================
# DIRECTORY STRUCTURE:
#   ~/msp/
#     clients/          # One subdirectory per client
#       [client-name]/
#         health/       # System health snapshots
#         incidents/    # Incident logs
#         audits/       # Security and compliance audits
#         reports/      # Generated client reports
#     tickets/          # Open and closed ticket logs
#     sla/              # SLA tracking files
#     reports/          # Cross-client MSP reports
#     audio/            # Narrated briefings
#     archives/         # Rotated data
#     logs/             # Script execution logs
# ============================================================
# CRON SCHEDULE:
#   */15 * * * *   health-check.sh          # Every 15 min health pulse
#   0 7  * * 1-5   morning-brief.sh         # Weekday morning brief
#   0 8  * * 1     weekly-review.sh         # Monday client reviews
#   0 6  1 * *     monthly-reports.sh       # Monthly client reports
#   0 2  * * *     nightly-audit.sh         # Nightly security audit
# ============================================================
# SETUP NOTES:
#   1. Add client names to CLIENTS array
#   2. Add client server IPs to ~/msp/clients/[name]/servers.txt
#   3. Configure SSH keys for each client server
#   4. Set SLA_RESPONSE_HOURS per your contracts

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
WEEK=$(date +%V)
MONTH=$(date +%B)
MSP_NAME="[Your MSP Name]"
SLA_RESPONSE_HOURS=4

# Add all managed clients here
CLIENTS=(
    "client-alpha"
    "client-beta"
    "client-gamma"
)

mkdir -p ~/msp/{tickets,sla,reports,audio,archives,logs}
for client in "${CLIENTS[@]}"; do
    mkdir -p ~/msp/clients/${client}/{health,incidents,audits,reports}
done

# ── USAGE ─────────────────────────────────────────────────
# Morning brief:        ./apex-template-msp.sh brief
# Health check all:     ./apex-template-msp.sh health
# New incident:         ./apex-template-msp.sh incident "client-alpha" "Server unreachable" "P1"
# Close ticket:         ./apex-template-msp.sh close-ticket "TKT-042"
# Weekly review:        ./apex-template-msp.sh weekly
# Client report:        ./apex-template-msp.sh client-report "client-alpha"
# Nightly audit:        ./apex-template-msp.sh audit

CMD=${1:-brief}

# ── HEALTH CHECK — ALL CLIENTS ────────────────────────────
health_check_all() {
    echo "[$(date)] Running health check..." >> ~/msp/logs/script.log

    for client in "${CLIENTS[@]}"; do
        (
            # Disk, memory, cpu, uptime via SSH per client
            apex "use shell to ssh ${client} and get disk usage memory usage \
            cpu load and uptime and write to ~/msp/clients/${client}/health/health-${DATE}-$(date +%H%M).txt"

            apex "read ~/msp/clients/${client}/health/health-${DATE}-$(date +%H%M).txt \
            and check for any critical thresholds disk over 90 percent memory over 85 percent \
            and write any alerts to ~/msp/clients/${client}/health/alerts-${DATE}.txt"
        ) &
    done

    wait

    # Aggregate health across all clients
    apex "read all alert files created today across all client directories in ~/msp/clients \
    and write a consolidated health alert summary to ~/msp/reports/health-summary-${DATE}-$(date +%H%M).txt"

    # Only narrate if alerts exist
    ALERT_SIZE=$(wc -c < ~/msp/reports/health-summary-${DATE}-$(date +%H%M).txt 2>/dev/null || echo 0)
    if [ "$ALERT_SIZE" -gt 50 ]; then
        apex "read ~/msp/reports/health-summary-${DATE}-$(date +%H%M).txt \
        and use espeak to announce critical alerts \
        and save to ~/msp/audio/health-alert-$(date +%H%M).wav"
        aplay ~/msp/audio/health-alert-$(date +%H%M).wav 2>/dev/null
    fi

    echo "[$(date)] Health check complete." >> ~/msp/logs/script.log
}

# ── MORNING BRIEF ─────────────────────────────────────────
morning_brief() {
    echo "[$(date)] Running morning brief..." >> ~/msp/logs/script.log

    # Parallel per-client snapshots
    for client in "${CLIENTS[@]}"; do
        apex "read all files in ~/msp/clients/${client}/health from yesterday \
        and ~/msp/clients/${client}/incidents and write a one paragraph status \
        summary for ${client} to ~/msp/clients/${client}/reports/status-${DATE}.txt" &
    done

    # Open tickets and SLA status
    apex "read ~/msp/tickets/open-tickets.txt and calculate how many tickets \
    are approaching or breaching ${SLA_RESPONSE_HOURS} hour SLA \
    and write urgent SLA alerts to ~/msp/sla/sla-status-${DATE}.txt" &

    wait

    # Consolidated MSP brief
    STATUSES=""
    for client in "${CLIENTS[@]}"; do
        STATUSES="${STATUSES} ~/msp/clients/${client}/reports/status-${DATE}.txt"
    done

    apex "read ${STATUSES} ~/msp/sla/sla-status-${DATE}.txt \
    ~/msp/tickets/open-tickets.txt \
    and write a structured ${DAY} morning operations brief for ${MSP_NAME} \
    with sections for each client status open tickets and SLA risks \
    to ~/msp/reports/morning-brief-${DATE}.txt"

    apex "read ~/msp/reports/morning-brief-${DATE}.txt \
    and use espeak in a professional voice at speed 145 \
    and save to ~/msp/audio/morning-brief-${DATE}.wav"

    aplay ~/msp/audio/morning-brief-${DATE}.wav 2>/dev/null

    echo "[$(date)] Morning brief complete." >> ~/msp/logs/script.log
}

# ── LOG NEW INCIDENT ──────────────────────────────────────
new_incident() {
    CLIENT=$2
    DESCRIPTION=$3
    PRIORITY=$4
    TICKET_ID="TKT-$(date +%s)"

    apex "write a new incident file for ticket ${TICKET_ID} \
    client ${CLIENT} priority ${PRIORITY} \
    description ${DESCRIPTION} opened ${DATE} $(date +%H:%M) \
    status OPEN \
    to ~/msp/clients/${CLIENT}/incidents/${TICKET_ID}.txt"

    apex "append ticket ${TICKET_ID} ${CLIENT} ${PRIORITY} opened ${DATE} ${DESCRIPTION} \
    to ~/msp/tickets/open-tickets.txt"

    apex "append SLA clock started for ${TICKET_ID} at $(date +%H:%M) \
    deadline in ${SLA_RESPONSE_HOURS} hours to ~/msp/sla/sla-log.txt"

    apex "use espeak to say new ${PRIORITY} incident created for ${CLIENT}: ${DESCRIPTION}"

    echo "Ticket created: ${TICKET_ID}"
    echo "[$(date)] Incident ${TICKET_ID} created for ${CLIENT}." >> ~/msp/logs/script.log
}

# ── CLOSE TICKET ──────────────────────────────────────────
close_ticket() {
    TICKET_ID=$2

    apex "read ~/msp/tickets/open-tickets.txt and remove the line containing \
    ${TICKET_ID} and write the updated file back"

    apex "append ${TICKET_ID} closed ${DATE} $(date +%H:%M) \
    to ~/msp/tickets/closed-tickets.txt"

    apex "use espeak to say ticket ${TICKET_ID} has been closed and archived"

    echo "[$(date)] Ticket ${TICKET_ID} closed." >> ~/msp/logs/script.log
}

# ── NIGHTLY SECURITY AUDIT ────────────────────────────────
nightly_audit() {
    echo "[$(date)] Running nightly audit..." >> ~/msp/logs/script.log

    for client in "${CLIENTS[@]}"; do
        (
            apex "use shell to ssh ${client} and check for failed login attempts \
            in auth.log in the last 24 hours and write count and top source IPs \
            to ~/msp/clients/${client}/audits/auth-audit-${DATE}.txt"

            apex "use shell to ssh ${client} and list all world-readable files \
            in sensitive directories and write to \
            ~/msp/clients/${client}/audits/permissions-audit-${DATE}.txt"

            apex "use shell to ssh ${client} and check for any new cron jobs \
            added in the last 24 hours and write to \
            ~/msp/clients/${client}/audits/cron-audit-${DATE}.txt"
        ) &
    done

    wait

    # Aggregate audit findings
    apex "read all audit files created today in ~/msp/clients \
    and write a consolidated security audit report for ${DATE} \
    flagging any critical findings to ~/msp/reports/security-audit-${DATE}.txt"

    apex "read ~/msp/reports/security-audit-${DATE}.txt \
    and use espeak in a serious voice to announce any critical security findings \
    and save to ~/msp/audio/security-audit-${DATE}.wav"

    echo "[$(date)] Nightly audit complete." >> ~/msp/logs/script.log
}

# ── WEEKLY REVIEW ─────────────────────────────────────────
weekly_review() {
    echo "[$(date)] Running weekly review..." >> ~/msp/logs/script.log

    # Per-client weekly reports in parallel
    for client in "${CLIENTS[@]}"; do
        apex "read all health and incident files for ${client} from this week \
        in ~/msp/clients/${client} and write a full weekly client report \
        with uptime estimate incident count resolution times and recommendations \
        to ~/msp/clients/${client}/reports/weekly-${DATE}.txt" &
    done

    # SLA compliance report
    apex "read ~/msp/sla/sla-log.txt and ~/msp/tickets/closed-tickets.txt \
    and calculate SLA compliance rate for week ${WEEK} \
    and write compliance report to ~/msp/sla/weekly-sla-${DATE}.txt" &

    wait

    # MSP-wide weekly summary
    WEEKLY_REPORTS=""
    for client in "${CLIENTS[@]}"; do
        WEEKLY_REPORTS="${WEEKLY_REPORTS} ~/msp/clients/${client}/reports/weekly-${DATE}.txt"
    done

    apex "read ${WEEKLY_REPORTS} ~/msp/sla/weekly-sla-${DATE}.txt \
    and write a comprehensive weekly MSP operations review for week ${WEEK} \
    with overall health summary per-client status SLA compliance and recommendations \
    to ~/msp/reports/weekly-review-${DATE}.txt"

    apex "read ~/msp/reports/weekly-review-${DATE}.txt \
    and use espeak in a confident professional voice at speed 140 \
    and save to ~/msp/audio/weekly-review-${DATE}.wav"

    aplay ~/msp/audio/weekly-review-${DATE}.wav 2>/dev/null

    # Archive old files
    apex "archive all daily files older than 7 days in ~/msp/reports \
    into ~/msp/archives/week-${WEEK}.tar.gz \
    then use espeak to say weekly review complete and archived"

    echo "[$(date)] Weekly review complete." >> ~/msp/logs/script.log
}

# ── INDIVIDUAL CLIENT REPORT ──────────────────────────────
client_report() {
    CLIENT=$2

    apex "read all files in ~/msp/clients/${CLIENT} including health incidents \
    and audits and write a comprehensive client-facing monthly report for ${MONTH} \
    suitable for presenting to the client covering uptime security incidents \
    resolved tickets and recommendations for next month \
    to ~/msp/clients/${CLIENT}/reports/client-report-${MONTH}.txt"

    apex "read ~/msp/clients/${CLIENT}/reports/client-report-${MONTH}.txt \
    and use espeak in a professional BBC voice at speed 135 \
    and save to ~/msp/audio/${CLIENT}-report-${MONTH}.wav"

    apex "use espeak to say client report for ${CLIENT} for ${MONTH} is ready"
    echo "[$(date)] Client report generated for ${CLIENT}." >> ~/msp/logs/script.log
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    brief)          morning_brief ;;
    health)         health_check_all ;;
    incident)       new_incident "$@" ;;
    close-ticket)   close_ticket "$@" ;;
    audit)          nightly_audit ;;
    weekly)         weekly_review ;;
    client-report)  client_report "$@" ;;
    *)              echo "Unknown command: $CMD" ;;
esac
