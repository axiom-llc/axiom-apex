#!/usr/bin/env bash
# ============================================================
# APEX REVENUE TEMPLATE 3 — MICRO-SAAS MONITORING SERVICE
# Model: Sell automated uptime/security reports as a service
# ROI profile: Recurring monthly revenue, near-zero marginal cost
# Est. return: $50-150/client/month, 20 clients = $1k-3k MRR
# ============================================================
# HOW IT WORKS:
#   1. You onboard a client (their domain/IP, their email)
#   2. APEX monitors their site/server every 15 min
#   3. Generates daily health reports narrated to WAV
#   4. Emails PDF-style reports weekly (via sendmail/msmtp)
#   5. Alerts client immediately on downtime or anomalies
#   6. You charge $50-150/month per client on retainer
#
# THIS IS ESSENTIALLY:
#   A stripped-down StatusPage + UptimeRobot + security scanner
#   running on a $6/month VPS that you fully own
#   Margin: ~95% after VPS cost
#
# TIERED PRICING MODEL:
#   Tier 1 ($50/mo)  — uptime monitoring + weekly report
#   Tier 2 ($100/mo) — + security audit + daily brief
#   Tier 3 ($150/mo) — + narrated WAV briefs + incident response
#
# DEPLOY AS DAEMON ON VPS:
#   1. git clone your scripts to /opt/apex-monitor
#   2. Set all cron jobs below
#   3. Each new client = one onboard command
#   4. Scales to 50+ clients on a single $12/month VPS
#
# CRON SCHEDULE:
#   */15 * * * *   ./apex-revenue-monitor.sh pulse-all
#   0 7  * * *     ./apex-revenue-monitor.sh daily-all
#   0 8  * * 1     ./apex-revenue-monitor.sh weekly-all
#   0 2  * * *     ./apex-revenue-monitor.sh audit-all
#   0 9  1 * *     ./apex-revenue-monitor.sh invoice-all
# ============================================================

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)
MONTH=$(date +%B)
YEAR=$(date +%Y)
SERVICE_NAME="[Your Service Name]"
YOUR_EMAIL="you@yourdomain.com"
YOUR_NAME="[Your Name]"

mkdir -p ~/monitor/{clients,reports,audio,invoices,alerts,logs,templates}

# ── CLIENT REGISTRY ───────────────────────────────────────
# ~/monitor/clients/[slug]/config.txt contains:
#   NAME, DOMAIN, IP, EMAIL, TIER, RATE, START_DATE

CMD=${1:-help}

# ── ONBOARD NEW CLIENT ────────────────────────────────────
onboard_client() {
    NAME=$2
    DOMAIN=$3
    IP=$4
    EMAIL=$5
    TIER=${6:-1}
    RATE=${7:-50}
    SLUG=$(echo "$NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

    mkdir -p ~/monitor/clients/${SLUG}/{health,incidents,audits,reports,audio}

    cat > ~/monitor/clients/${SLUG}/config.txt << EOF
NAME: ${NAME}
DOMAIN: ${DOMAIN}
IP: ${IP}
EMAIL: ${EMAIL}
TIER: ${TIER}
RATE: ${RATE}
START_DATE: ${DATE}
SLUG: ${SLUG}
EOF

    # Register in master client list
    apex "append client ${SLUG} name ${NAME} domain ${DOMAIN} tier ${TIER} \
    rate ${RATE} started ${DATE} \
    to ~/monitor/clients/client-registry.txt"

    # Generate welcome report
    apex "write a professional welcome report for new monitoring client ${NAME} \
    for domain ${DOMAIN} tier ${TIER} service starting ${DATE} \
    from ${SERVICE_NAME} covering what is monitored frequency of reports \
    and how to contact for incidents \
    to ~/monitor/clients/${SLUG}/reports/welcome-${DATE}.txt"

    # Send welcome email
    apex "use shell to cat ~/monitor/clients/${SLUG}/reports/welcome-${DATE}.txt \
    | mail -s 'Welcome to ${SERVICE_NAME} — Monitoring Active for ${DOMAIN}' ${EMAIL}"

    apex "use espeak to say new client ${NAME} onboarded at tier ${TIER}"
    echo "[${DATE}] Client onboarded: ${SLUG}" >> ~/monitor/logs/onboard.log
}

# ── HEALTH PULSE — SINGLE CLIENT ─────────────────────────
pulse_client() {
    SLUG=$1
    source <(grep -E '^(NAME|DOMAIN|IP|EMAIL|TIER):' ~/monitor/clients/${SLUG}/config.txt \
             | sed 's/: /="/' | sed 's/$/"/')

    # HTTP check
    apex "use shell to curl -o /dev/null -s -w '%{http_code} %{time_total}' \
    https://${DOMAIN} and write result to \
    ~/monitor/clients/${SLUG}/health/pulse-${DATE}-${TIME//:/}.txt"

    # Parse result and alert on non-200
    apex "read ~/monitor/clients/${SLUG}/health/pulse-${DATE}-${TIME//:/}.txt \
    and if status code is not 200 write a downtime alert to \
    ~/monitor/alerts/${SLUG}-down-${DATE}-${TIME//:/}.txt"

    # Check if alert file was created
    if [ -f ~/monitor/alerts/${SLUG}-down-${DATE}-${TIME//:/}.txt ]; then
        fire_alert "$SLUG" "$NAME" "$DOMAIN" "$EMAIL" "$TIME"
    fi
}

# ── FIRE DOWNTIME ALERT ───────────────────────────────────
fire_alert() {
    SLUG=$1; NAME=$2; DOMAIN=$3; EMAIL=$4; ALERT_TIME=$5

    apex "write a professional downtime alert email for client ${NAME} \
    domain ${DOMAIN} detected at ${ALERT_TIME} on ${DATE} \
    stating the issue was detected automatically and is being investigated \
    to ~/monitor/alerts/${SLUG}-alert-email-${DATE}.txt"

    apex "use shell to cat ~/monitor/alerts/${SLUG}-alert-email-${DATE}.txt \
    | mail -s 'ALERT: ${DOMAIN} appears to be down — ${ALERT_TIME}' \
    ${EMAIL} ${YOUR_EMAIL}"

    apex "use espeak to say alert fired for client ${NAME} domain ${DOMAIN} is down"

    apex "append downtime alert ${SLUG} ${DOMAIN} ${DATE} ${ALERT_TIME} \
    to ~/monitor/logs/alerts.log"
}

# ── PULSE ALL CLIENTS ─────────────────────────────────────
pulse_all() {
    for client_dir in ~/monitor/clients/*/; do
        SLUG=$(basename "$client_dir")
        [ "$SLUG" = "client-registry.txt" ] && continue
        [ -f "${client_dir}config.txt" ] || continue
        pulse_client "$SLUG" &
    done
    wait
}

# ── DAILY REPORT — SINGLE CLIENT ─────────────────────────
daily_report_client() {
    SLUG=$1
    source <(grep -E '^(NAME|DOMAIN|IP|EMAIL|TIER|RATE):' \
             ~/monitor/clients/${SLUG}/config.txt \
             | sed 's/: /="/' | sed 's/$/"/')

    # Aggregate today's health pulses
    apex "read all pulse files in ~/monitor/clients/${SLUG}/health created today \
    and calculate uptime percentage average response time \
    and any downtime incidents \
    and write daily health summary to \
    ~/monitor/clients/${SLUG}/reports/daily-${DATE}.txt"

    # Tier 2+ get security check
    if [ "${TIER}" -ge 2 ]; then
        apex "use shell to curl -s https://${DOMAIN} | grep -i \
        'server:\|x-powered-by:\|strict-transport-security:' \
        and write security header analysis to \
        ~/monitor/clients/${SLUG}/audits/headers-${DATE}.txt"
    fi

    # Tier 3 gets narrated WAV
    if [ "${TIER}" -ge 3 ]; then
        apex "read ~/monitor/clients/${SLUG}/reports/daily-${DATE}.txt \
        and use espeak in a professional BBC voice at speed 140 \
        and save to ~/monitor/clients/${SLUG}/audio/daily-${DATE}.wav"
    fi

    echo "[${DATE}] Daily report complete: ${SLUG}" >> ~/monitor/logs/daily.log
}

# ── DAILY ALL CLIENTS ─────────────────────────────────────
daily_all() {
    for client_dir in ~/monitor/clients/*/; do
        SLUG=$(basename "$client_dir")
        [ -f "${client_dir}config.txt" ] || continue
        daily_report_client "$SLUG" &
    done
    wait
    apex "use espeak to say daily reports complete for all clients"
}

# ── WEEKLY CLIENT REPORT + EMAIL ─────────────────────────
weekly_report_client() {
    SLUG=$1
    source <(grep -E '^(NAME|DOMAIN|IP|EMAIL|TIER|RATE):' \
             ~/monitor/clients/${SLUG}/config.txt \
             | sed 's/: /="/' | sed 's/$/"/')

    # Aggregate week's data
    apex "read all daily report files from this week \
    in ~/monitor/clients/${SLUG}/reports \
    and write a comprehensive weekly monitoring report for ${NAME} \
    covering domain ${DOMAIN} \
    with sections for weekly uptime percentage \
    total downtime minutes if any \
    average response time trend \
    security observations if tier 2 or above \
    and recommendations for next week \
    formatted professionally from ${SERVICE_NAME} \
    to ~/monitor/clients/${SLUG}/reports/weekly-${DATE}.txt"

    # Email weekly report
    apex "use shell to cat ~/monitor/clients/${SLUG}/reports/weekly-${DATE}.txt \
    | mail -s 'Weekly Monitoring Report — ${DOMAIN} — Week of ${DATE}' \
    ${EMAIL}"

    echo "[${DATE}] Weekly report sent: ${SLUG} → ${EMAIL}" >> ~/monitor/logs/weekly.log
}

# ── WEEKLY ALL CLIENTS ────────────────────────────────────
weekly_all() {
    for client_dir in ~/monitor/clients/*/; do
        SLUG=$(basename "$client_dir")
        [ -f "${client_dir}config.txt" ] || continue
        weekly_report_client "$SLUG" &
    done
    wait
    apex "use espeak to say weekly reports sent to all clients"
}

# ── GENERATE MONTHLY INVOICE ──────────────────────────────
generate_invoice() {
    SLUG=$1
    source <(grep -E '^(NAME|DOMAIN|IP|EMAIL|TIER|RATE|START_DATE):' \
             ~/monitor/clients/${SLUG}/config.txt \
             | sed 's/: /="/' | sed 's/$/"/')

    INVOICE_NUM="INV-${SLUG^^}-$(date +%Y%m)"

    apex "write a professional plain text invoice numbered ${INVOICE_NUM} \
    from ${YOUR_NAME} ${SERVICE_NAME} ${YOUR_EMAIL} \
    to client ${NAME} \
    for monitoring services for domain ${DOMAIN} \
    billing period ${MONTH} ${YEAR} \
    tier ${TIER} monitoring package \
    amount due ${RATE} USD \
    due date 30 days from ${DATE} \
    payment methods bank transfer PayPal or crypto on request \
    to ~/monitor/invoices/${INVOICE_NUM}.txt"

    # Email invoice
    apex "use shell to cat ~/monitor/invoices/${INVOICE_NUM}.txt \
    | mail -s 'Invoice ${INVOICE_NUM} — ${SERVICE_NAME} — ${MONTH} ${YEAR}' \
    ${EMAIL}"

    apex "append invoice ${INVOICE_NUM} ${SLUG} ${RATE} sent ${DATE} \
    to ~/monitor/invoices/invoice-ledger.txt"

    echo "[${DATE}] Invoice sent: ${INVOICE_NUM} → ${EMAIL}" >> ~/monitor/logs/invoices.log
}

# ── INVOICE ALL CLIENTS ───────────────────────────────────
invoice_all() {
    for client_dir in ~/monitor/clients/*/; do
        SLUG=$(basename "$client_dir")
        [ -f "${client_dir}config.txt" ] || continue
        generate_invoice "$SLUG" &
    done
    wait

    # Revenue summary
    apex "read ~/monitor/invoices/invoice-ledger.txt \
    and calculate total monthly recurring revenue for ${MONTH} \
    and write revenue summary to ~/monitor/reports/mrr-${MONTH}.txt"

    apex "read ~/monitor/reports/mrr-${MONTH}.txt \
    and use espeak in a satisfied tone and save to ~/monitor/audio/mrr-${MONTH}.wav"

    aplay ~/monitor/audio/mrr-${MONTH}.wav 2>/dev/null
}

# ── MRR DASHBOARD ─────────────────────────────────────────
mrr_dashboard() {
    apex "read ~/monitor/clients/client-registry.txt \
    ~/monitor/invoices/invoice-ledger.txt \
    ~/monitor/logs/alerts.log \
    and write a business dashboard showing \
    total active clients \
    monthly recurring revenue \
    total alerts fired this month \
    client retention and churn \
    to ~/monitor/reports/dashboard-${DATE}.txt"

    apex "read ~/monitor/reports/dashboard-${DATE}.txt \
    and use espeak in Morgan Freeman's voice at speed 135 \
    and save to ~/monitor/audio/dashboard-${DATE}.wav"

    aplay ~/monitor/audio/dashboard-${DATE}.wav 2>/dev/null
}

# ── AUDIT ALL ─────────────────────────────────────────────
audit_all() {
    for client_dir in ~/monitor/clients/*/; do
        SLUG=$(basename "$client_dir")
        [ -f "${client_dir}config.txt" ] || continue
        source <(grep -E '^(DOMAIN|TIER):' "${client_dir}config.txt" \
                 | sed 's/: /="/' | sed 's/$/"/')
        [ "${TIER}" -ge 2 ] || continue
        apex "use shell to curl -s -I https://${DOMAIN} \
        and analyze response headers for security issues \
        and write to ~/monitor/clients/${SLUG}/audits/nightly-${DATE}.txt" &
    done
    wait
}

# ── HELP ──────────────────────────────────────────────────
show_help() {
cat << EOF
apex-revenue-monitor.sh — Micro-SaaS monitoring service

Commands:
  onboard "Name" domain.com 1.2.3.4 email@client.com [tier] [rate]
  pulse-all                 — Health check all clients (run every 15min)
  daily-all                 — Daily reports all clients (run 7am)
  weekly-all                — Weekly reports + email all clients (run Mon 8am)
  audit-all                 — Nightly security audit tier 2+ (run 2am)
  invoice-all               — Monthly invoices all clients (run 1st of month)
  mrr-dashboard             — Current MRR and business stats
EOF
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    onboard)        onboard_client "$@" ;;
    pulse-all)      pulse_all ;;
    daily-all)      daily_all ;;
    weekly-all)     weekly_all ;;
    audit-all)      audit_all ;;
    invoice-all)    invoice_all ;;
    mrr-dashboard)  mrr_dashboard ;;
    help)           show_help ;;
    *)              echo "Unknown: $CMD. Run ./apex-revenue-monitor.sh help" ;;
esac
