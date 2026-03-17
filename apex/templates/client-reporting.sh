#!/usr/bin/env bash
# ============================================================
# client-reporting.sh — Automated client report generation + delivery
# Aggregates project/service data, generates branded reports, emails on schedule.
# Requires: apex, msmtp (or sendmail/mail)
# Config:   ~/.config/apex/agency_name — your agency/firm name
#           ~/.config/apex/agency_email — your reply-to address
#           SMTP_CMD — mail delivery command (default: msmtp)
# Cron:     0 9 * * 5   ./client-reporting.sh weekly-all
#           0 9 1 * *    ./client-reporting.sh monthly-all
# Client registry: ~/reporting/clients/<slug>/config.txt
#   NAME, EMAIL, TYPE (agency|rcm|monitor|legal), DATA_PATH, RATE
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

AGENCY="${AGENCY:-$(cat ~/.config/apex/agency_name 2>/dev/null || echo "Your Agency")}"
AGENCY_EMAIL="${AGENCY_EMAIL:-$(cat ~/.config/apex/agency_email 2>/dev/null || echo "you@yourdomain.com")}"
SMTP_CMD="${SMTP_CMD:-msmtp}"
DATE=$(date +%Y-%m-%d)
WEEK=$(date +%V)
MONTH=$(date +%B_%Y)

mkdir -p ~/reporting/{clients,reports,sent,logs,archives,templates}

CMD=${1:-help}

# ── ONBOARD CLIENT ────────────────────────────────────────
onboard() {
    NAME="$2"; EMAIL="$3"; TYPE="${4:-agency}"; DATA_PATH="${5:-~/agency}"; RATE="${6:-0}"
    SLUG=$(slugify "$NAME")

    mkdir -p ~/reporting/clients/${SLUG}/{reports,sent}

    cat > ~/reporting/clients/${SLUG}/config.txt << EOF
NAME: ${NAME}
EMAIL: ${EMAIL}
TYPE: ${TYPE}
DATA_PATH: ${DATA_PATH}
RATE: ${RATE}
SLUG: ${SLUG}
ONBOARDED: ${DATE}
EOF

    apex "append client ${SLUG} name ${NAME} type ${TYPE} email ${EMAIL} onboarded ${DATE} \
    to ~/reporting/clients/client-registry.txt"

    apex "write a brief welcome email from ${AGENCY} to ${NAME} confirming \
    that automated reporting is now active, report frequency (weekly + monthly), \
    and that reports will arrive from ${AGENCY_EMAIL} \
    write to ~/reporting/clients/${SLUG}/sent/welcome-${DATE}.txt"

    _send_email "$EMAIL" "Automated Reporting Active — ${AGENCY}" \
        ~/reporting/clients/${SLUG}/sent/welcome-${DATE}.txt

    echo "[${DATE}] Client onboarded: ${SLUG}" >> ~/reporting/logs/reporting.log
    echo "✓ ${NAME} onboarded. Config: ~/reporting/clients/${SLUG}/config.txt"
}

# ── SINGLE CLIENT REPORT ──────────────────────────────────
report() {
    SLUG="$1"
    PERIOD="${2:-weekly}"
    local config=~/reporting/clients/${SLUG}/config.txt
    require_file "$config" "client config not found for slug: ${SLUG}"

    load_config "$config" NAME EMAIL TYPE DATA_PATH RATE

    local outfile=~/reporting/clients/${SLUG}/reports/${PERIOD}-${DATE}.txt

    # Build a type-appropriate report
    case "$TYPE" in
        agency)
            apex "read all project files, timesheets, invoices, and weekly reports \
            in ${DATA_PATH}/projects/ and ${DATA_PATH}/invoices/ created in the last 7 days \
            using read_file
            write a professional ${PERIOD} client report for ${NAME} from ${AGENCY}:
            WORK COMPLETED: specific deliverables with time logged
            HOURS AND FEES: itemised or summarised based on fee arrangement
            IN PROGRESS: active work items and expected completion
            NEXT PERIOD: planned work for next week
            ACTION REQUIRED: anything we need from the client
            tone: clear, professional, no jargon
            under 400 words
            write to ${outfile}"
            ;;
        monitor)
            apex "read all health reports, alert logs, and audit files \
            in ${DATA_PATH}/clients/${SLUG}/ created in the last 7 days using read_file
            write a professional ${PERIOD} monitoring report for ${NAME} from ${AGENCY}:
            UPTIME SUMMARY: percentage and any downtime incidents with timestamps
            PERFORMANCE: average response time trend
            SECURITY: header audit findings or changes
            ALERTS FIRED: count and resolution
            NEXT PERIOD: what we are watching
            under 350 words
            write to ${outfile}"
            ;;
        rcm)
            apex "read all RCM reports in ${DATA_PATH}/reports/ from the last 7 days using read_file
            write a professional ${PERIOD} revenue cycle report for ${NAME} from ${AGENCY}:
            CLAIMS SUBMITTED | PAYMENTS POSTED | DENIAL RATE |
            DAYS IN AR | COLLECTION RATE | OPEN ITEMS REQUIRING ATTENTION
            under 350 words
            write to ${outfile}"
            ;;
        legal)
            apex "read all matter files, timesheets, and deadline reports \
            in ${DATA_PATH} from the last 7 days using read_file
            write a professional ${PERIOD} matter status report for ${NAME} from ${AGENCY}:
            ACTIVE MATTERS: status and next steps for each
            TIME LOGGED: hours and fees this period
            UPCOMING DEADLINES: any dates requiring client awareness
            ACTION REQUIRED: anything we need from client
            under 400 words
            write to ${outfile}"
            ;;
        *)
            apex "read all files in ${DATA_PATH} created in the last 7 days using read_file
            write a professional ${PERIOD} report for ${NAME} from ${AGENCY}
            summarising work completed, current status, and next steps
            write to ${outfile}"
            ;;
    esac

    # Send
    local subject="${PERIOD^} Report — ${NAME} — ${DATE} — ${AGENCY}"
    _send_email "$EMAIL" "$subject" "$outfile"

    apex "append ${SLUG} ${PERIOD} ${DATE} sent ${EMAIL} \
    to ~/reporting/logs/sent-log.txt"

    log ~/reporting/logs/reporting.log "Report sent: ${SLUG} ${PERIOD} → ${EMAIL}"
    echo "✓ ${PERIOD} report sent: ${NAME} → ${EMAIL}"
}

# ── WEEKLY ALL CLIENTS ────────────────────────────────────
weekly_all() {
    PIDS=()
    for client_dir in ~/reporting/clients/*/; do
        SLUG=$(basename "$client_dir")
        [[ -f "${client_dir}config.txt" ]] || continue
        ( report "$SLUG" weekly ) &
        PIDS+=($!)
    done
    wait_pids "${PIDS[@]}" || true

    # Summary
    apex "read ~/reporting/logs/sent-log.txt using read_file
    count reports sent this week write summary to ~/reporting/reports/weekly-summary-${WEEK}-${DATE}.txt"
    cat ~/reporting/reports/weekly-summary-${WEEK}-${DATE}.txt
}

# ── MONTHLY ALL CLIENTS ───────────────────────────────────
monthly_all() {
    PIDS=()
    for client_dir in ~/reporting/clients/*/; do
        SLUG=$(basename "$client_dir")
        [[ -f "${client_dir}config.txt" ]] || continue

        load_config "${client_dir}config.txt" NAME EMAIL TYPE DATA_PATH RATE
        local outfile=~/reporting/clients/${SLUG}/reports/monthly-${MONTH}.txt
        local invoice_total=""

        # Monthly adds financial summary + invoice note
        apex "read all ${DATA_PATH} files from this month using read_file
        write a comprehensive monthly report for ${NAME} from ${AGENCY}:
        MONTH IN REVIEW: key accomplishments and deliverables
        METRICS: all relevant KPIs for this client type (${TYPE})
        FINANCIAL SUMMARY: fees for the month${RATE:+, total: \$${RATE}}
        RECOMMENDATIONS: 2-3 specific improvements for next month
        LOOKING AHEAD: planned work for next month
        write to ${outfile}" &

        PIDS+=($!)
    done

    for pid in "${PIDS[@]}"; do
        wait "$pid" || true
        # Send after each completes
    done

    for client_dir in ~/reporting/clients/*/; do
        SLUG=$(basename "$client_dir")
        local outfile=~/reporting/clients/${SLUG}/reports/monthly-${MONTH}.txt
        [[ -f "$outfile" ]] || continue
        load_config "${client_dir}config.txt" NAME EMAIL
        _send_email "$EMAIL" "Monthly Report — ${NAME} — ${MONTH} — ${AGENCY}" "$outfile"
    done
}

# ── SEND EMAIL ────────────────────────────────────────────
_send_email() {
    local to="$1"; local subject="$2"; local body_file="$3"
    require_file "$body_file" "body file missing"

    if command -v "$SMTP_CMD" &>/dev/null; then
        cat "$body_file" | $SMTP_CMD -t << HEADERS
To: ${to}
From: ${AGENCY} <${AGENCY_EMAIL}>
Subject: ${subject}
Content-Type: text/plain; charset=UTF-8

HEADERS
    elif command -v mail &>/dev/null; then
        mail -s "$subject" -r "$AGENCY_EMAIL" "$to" < "$body_file"
    else
        echo "⚠ No mail command available. Report saved to: ${body_file}"
        echo "  Would have emailed to: ${to}"
        echo "  Subject: ${subject}"
    fi
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    onboard)      onboard "$@" ;;
    report)       report "$2" "${3:-weekly}" ;;
    weekly-all)   weekly_all ;;
    monthly-all)  monthly_all ;;
    help|*)
        echo "Commands:"
        echo "  onboard \"Client Name\" email@client.com [agency|monitor|rcm|legal] [data_path] [rate]"
        echo "  report <slug> [weekly|monthly]"
        echo "  weekly-all   — send weekly reports to all clients (cron: 0 9 * * 5)"
        echo "  monthly-all  — send monthly reports to all clients (cron: 0 9 1 * *)"
        ;;
esac
