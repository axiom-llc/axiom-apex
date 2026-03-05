#!/usr/bin/env bash
# ============================================================
# cybersecurity.sh — Threat intelligence and security operations
# Requires: apex
# Config:   ASSETS_FILE — one IP/domain per line to monitor
#           ORG_NAME    — your organization name
# Cron:     */30 * * * *  ./cybersecurity.sh pulse
#           0 6  * * 1-5  ./cybersecurity.sh morning
#           0 2  * * *    ./cybersecurity.sh threat-sweep
#           0 3  * * *    ./cybersecurity.sh vuln-scan
#           0 7  * * 1    ./cybersecurity.sh weekly
# ============================================================
set -euo pipefail

ORG="${ORG_NAME:-$(cat ~/.config/apex/sec_org 2>/dev/null || echo "Your Organization")}"
ASSETS_FILE="${ASSETS_FILE:-${HOME}/.config/apex/sec_assets}"
DATE=$(date +%Y-%m-%d)
WEEK=$(date +%V)
TIME=$(date +%H%M)

mkdir -p ~/security/{intel,alerts,incidents,vulns,reports,logs,archives}

CMD=${1:-morning}

# ── PULSE — CONTINUOUS MONITORING ────────────────────────
pulse() {
    [[ ! -f "$ASSETS_FILE" ]] && echo "✗ Assets file not found: $ASSETS_FILE" && exit 1

    PIDS=()
    while IFS= read -r asset; do
        [[ -z "$asset" ]] && continue
        slug=$(echo "$asset" | tr '/.:' '_')
        (
            apex "use shell to check reachability and basic headers for ${asset}:
            curl -s -o /dev/null -w '%{http_code} %{time_total} %{size_download}' \
            --max-time 10 https://${asset} 2>/dev/null || echo 'UNREACHABLE'
            write result to ~/security/intel/pulse-${slug}-${DATE}-${TIME}.txt"

            # Alert on unreachable
            apex "read ~/security/intel/pulse-${slug}-${DATE}-${TIME}.txt using read_file
            if result shows UNREACHABLE or non-200 status
            write alert to ~/security/alerts/down-${slug}-${DATE}-${TIME}.txt"
        ) &
        PIDS+=($!)
    done < "$ASSETS_FILE"

    for pid in "${PIDS[@]}"; do wait "$pid" || true; done

    # Check for new alerts
    NEW_ALERTS=$(find ~/security/alerts/ -name "*-${DATE}-${TIME}.txt" 2>/dev/null | wc -l)
    [[ "$NEW_ALERTS" -gt 0 ]] && echo "⚠ ${NEW_ALERTS} alert(s) at ${TIME}" && \
        cat ~/security/alerts/*-${DATE}-${TIME}.txt
}

# ── MORNING SECURITY BRIEF ────────────────────────────────
morning() {
    echo "[${DATE}] Morning security brief..." >> ~/security/logs/sec.log

    # Parallel: threat intel + auth review + overnight alerts
    apex "fetch https://otx.alienvault.com/api/v1/pulses/subscribed?limit=10 using http_get
    extract threat indicators relevant to infrastructure and web applications
    write to ~/security/intel/otx-${DATE}.txt" &

    apex "fetch https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json \
    using http_get
    extract any CVEs added in the last 7 days
    write to ~/security/intel/cisa-kev-${DATE}.txt" &

    apex "use shell to grep 'Failed password\|Invalid user\|authentication failure' \
    /var/log/auth.log 2>/dev/null | tail -100
    summarise: total failures top source IPs targeted accounts
    write to ~/security/intel/auth-review-${DATE}.txt" &

    wait

    # Overnight alert summary
    OVERNIGHT_ALERTS=$(find ~/security/alerts/ -newer ~/security/logs/sec.log \
        -name "*.txt" 2>/dev/null | wc -l)

    apex "read ~/security/intel/otx-${DATE}.txt
    ~/security/intel/cisa-kev-${DATE}.txt
    ~/security/intel/auth-review-${DATE}.txt using read_file
    write morning security brief for ${ORG} on ${DATE}:
    THREAT LANDSCAPE: active campaigns or IOCs relevant to our profile
    NEW EXPLOITED VULNERABILITIES: CISA KEV additions requiring immediate attention
    AUTHENTICATION ANOMALIES: suspicious login patterns or brute force activity
    OVERNIGHT ALERTS: ${OVERNIGHT_ALERTS} asset alerts requiring review
    PRIORITY ACTIONS: ranked by severity
    write to ~/security/reports/morning-${DATE}.txt"

    cat ~/security/reports/morning-${DATE}.txt
    echo "[${DATE}] Morning brief complete." >> ~/security/logs/sec.log
}

# ── THREAT SWEEP — DARK WEB + PASTE MONITORING ───────────
threat_sweep() {
    [[ ! -f "$ASSETS_FILE" ]] && echo "✗ Assets file not found: $ASSETS_FILE" && exit 1

    DOMAINS=$(grep -v '^\s*$' "$ASSETS_FILE" | head -10 | tr '\n' ' ')

    PIDS=()

    # HackerNews for breach mentions
    for domain in $DOMAINS; do
        query=$(echo "$domain" | tr '.' '+')
        (
            apex "fetch https://hn.algolia.com/api/v1/search?query=${query}+breach+hack+leak \
            using http_get
            extract any mentions of ${domain} in security incidents
            write to ~/security/intel/hn-threat-${domain//\./}-${DATE}.txt"
        ) &
        PIDS+=($!)
    done

    # General threat landscape
    apex "fetch https://feeds.feedburner.com/TheHackersNews using http_get
    extract top security stories from last 24 hours
    flag any stories relevant to: web applications APIs cloud infrastructure authentication
    write to ~/security/intel/thn-${DATE}.txt" &

    PIDS+=($!)

    for pid in "${PIDS[@]}"; do wait "$pid" || true; done

    apex "read all intel files created today in ~/security/intel using read_file
    identify any direct exposure or relevant threat patterns for ${ORG}
    write threat sweep report to ~/security/reports/threat-sweep-${DATE}.txt"

    cat ~/security/reports/threat-sweep-${DATE}.txt
}

# ── VULNERABILITY SCAN ────────────────────────────────────
vuln_scan() {
    [[ ! -f "$ASSETS_FILE" ]] && echo "✗ Assets file not found: $ASSETS_FILE" && exit 1

    PIDS=()
    while IFS= read -r asset; do
        [[ -z "$asset" ]] && continue
        (
            apex "perform a passive vulnerability assessment for ${asset}:
            use shell to:
            - curl -s -I https://${asset} to check security headers
            - Check for: Strict-Transport-Security X-Content-Type-Options
              X-Frame-Options Content-Security-Policy Referrer-Policy
            - curl -s https://${asset}/robots.txt to check for exposed paths
            - dig ${asset} to review DNS configuration
            rate each finding: CRITICAL | HIGH | MEDIUM | LOW | INFO
            write to ~/security/vulns/${asset//\./}-${DATE}.txt"
        ) &
        PIDS+=($!)
    done < "$ASSETS_FILE"

    for pid in "${PIDS[@]}"; do wait "$pid" || true; done

    apex "read all vulnerability files created today in ~/security/vulns using read_file
    write consolidated vulnerability report for ${ORG} on ${DATE}:
    CRITICAL and HIGH findings first with remediation steps
    MEDIUM findings with recommended fixes
    OVERALL SECURITY POSTURE: score 1-10 with rationale
    write to ~/security/reports/vuln-report-${DATE}.txt"

    cat ~/security/reports/vuln-report-${DATE}.txt
}

# ── INCIDENT RESPONSE ─────────────────────────────────────
incident() {
    DESCRIPTION="$2"
    SEVERITY="${3:-HIGH}"
    [[ -z "$DESCRIPTION" ]] && echo "Usage: $0 incident \"description\" [CRITICAL|HIGH|MEDIUM]" && exit 1

    INCIDENT_ID="INC-$(date +%s)"

    apex "open a security incident for ${ORG}:
    ID: ${INCIDENT_ID}
    Severity: ${SEVERITY}
    Description: ${DESCRIPTION}
    Detected: ${DATE} $(date +%H:%M)

    Write incident response playbook covering:
    IMMEDIATE CONTAINMENT: first 15 minutes — what to isolate, disable, or preserve
    INVESTIGATION STEPS: evidence to collect, logs to review, systems to examine
    STAKEHOLDER NOTIFICATION: who to notify and when based on severity ${SEVERITY}
    RECOVERY STEPS: how to restore normal operations safely
    POST-INCIDENT: what to document, change, or improve

    Write to ~/security/incidents/${INCIDENT_ID}-${DATE}.txt"

    echo "Incident created: ${INCIDENT_ID}"
    cat ~/security/incidents/${INCIDENT_ID}-${DATE}.txt
    echo "[${DATE}] Incident ${INCIDENT_ID} opened: ${DESCRIPTION}" >> ~/security/logs/incidents.log
}

# ── WEEKLY SECURITY REPORT ────────────────────────────────
weekly() {
    apex "read all reports and intel from this week in ~/security using read_file
    write weekly security report for ${ORG} week ${WEEK}:
    INCIDENTS: opened closed in-progress
    VULNERABILITY POSTURE: new findings remediated outstanding by severity
    THREAT LANDSCAPE: notable campaigns IOCs relevant to our profile
    AUTHENTICATION: failed login trends anomalies
    ASSET COVERAGE: monitoring completeness
    WEEK-OVER-WEEK: improving | stable | degrading
    write to ~/security/reports/weekly-${WEEK}-${DATE}.txt"

    cat ~/security/reports/weekly-${WEEK}-${DATE}.txt
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    pulse)        pulse ;;
    morning)      morning ;;
    threat-sweep) threat_sweep ;;
    vuln-scan)    vuln_scan ;;
    incident)     incident "$@" ;;
    weekly)       weekly ;;
    *)            echo "Commands: pulse | morning | threat-sweep | vuln-scan | incident <desc> [severity] | weekly" ;;
esac
