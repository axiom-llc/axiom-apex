#!/usr/bin/env bash
# ============================================================
# APEX REVENUE TEMPLATE 1 — AUTOMATED PROPOSAL ENGINE
# Model: Freelance / Consulting lead generation
# ROI profile: Low setup cost, direct revenue, scales linearly
# Est. return: 2-5 new clients/month on autopilot
# ============================================================
# HOW IT WORKS:
#   1. Fetches job postings from public APIs (freelancer/upwork RSS)
#   2. Scores them against your skills profile
#   3. Auto-generates tailored proposals for high-score matches
#   4. Writes proposals to review queue — you approve, then send
#   5. Tracks win/loss rate over time in SQLite via apex memory
#
# HUMAN TOUCHPOINTS (semi-autonomous):
#   - Review and send approved proposals (5 min/proposal)
#   - Occasional skill profile updates
#
# DEPLOYMENT:
#   VPS cron every 2 hours during business hours
#   0 8-18/2 * * 1-5  ./apex-revenue-proposals.sh scan
# ============================================================

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)
mkdir -p ~/proposals/{queue,approved,sent,won,lost,reports,logs}

# ── CONFIGURE YOUR PROFILE ────────────────────────────────
# Edit this file with your actual skills, rates, and preferences
PROFILE_FILE=~/proposals/profile.txt
if [ ! -f "$PROFILE_FILE" ]; then
cat > "$PROFILE_FILE" << 'EOF'
SKILLS: Linux, bash, Python, IT consulting, automation, APEX, DevOps, shell scripting, system administration, cron, VPS management, security auditing, MSP workflows
RATE_MIN: 75
RATE_MAX: 200
PREFERRED: automation, IT consulting, DevOps, system administration, scripting
AVOID: PHP, mobile apps, graphic design, data entry
TONE: professional, direct, technical, confident
EXPERIENCE: 10+ years independent IT consultant, Linux specialist, automation architect
EOF
fi

CMD=${1:-scan}

# ── SCAN FOR JOB OPPORTUNITIES ────────────────────────────
scan_jobs() {
    echo "[${DATE} ${TIME}] Scanning for opportunities..." >> ~/proposals/logs/scan.log

    # Fetch job feeds — replace with actual RSS/API endpoints you have access to
    apex "fetch https://www.freelancer.com/jobs/linux-administration.rss using curl \
    and write raw feed to ~/proposals/queue/feed-linux-${DATE}.xml" &

    apex "fetch https://www.freelancer.com/jobs/shell-scripting.rss using curl \
    and write raw feed to ~/proposals/queue/feed-shell-${DATE}.xml" &

    apex "fetch https://www.freelancer.com/jobs/devops-sysadmin.rss using curl \
    and write raw feed to ~/proposals/queue/feed-devops-${DATE}.xml" &

    wait

    # Parse and score against profile
    apex "read all XML feed files in ~/proposals/queue created today \
    and extract job titles descriptions budgets and URLs \
    then read ~/proposals/profile.txt \
    and score each job 1-10 for fit based on skills and rate preferences \
    and write scored job list sorted by score descending \
    to ~/proposals/queue/scored-jobs-${DATE}.txt"

    # Extract high-score matches only (score 7+)
    apex "read ~/proposals/queue/scored-jobs-${DATE}.txt \
    and extract only jobs with score 7 or higher \
    and write to ~/proposals/queue/high-match-${DATE}.txt"

    MATCH_COUNT=$(wc -l < ~/proposals/queue/high-match-${DATE}.txt 2>/dev/null || echo 0)

    apex "use espeak to say ${MATCH_COUNT} high match jobs found on ${DATE}"

    echo "[${DATE} ${TIME}] Found ${MATCH_COUNT} high-match jobs." >> ~/proposals/logs/scan.log

    # Auto-generate proposals for top matches
    if [ "$MATCH_COUNT" -gt 0 ]; then
        generate_proposals
    fi
}

# ── GENERATE PROPOSALS ────────────────────────────────────
generate_proposals() {
    echo "[${DATE} ${TIME}] Generating proposals..." >> ~/proposals/logs/scan.log

    # Read high matches and generate one proposal per job
    apex "read ~/proposals/queue/high-match-${DATE}.txt \
    and ~/proposals/profile.txt \
    and for each job in the high match list write a tailored professional \
    freelance proposal of 200-300 words that references the specific job requirements \
    uses the consultant profile skills and experience \
    includes a confident rate range and clear call to action \
    write each proposal as a separate numbered section \
    to ~/proposals/queue/proposals-draft-${DATE}.txt"

    # Split into individual files for review
    apex "read ~/proposals/queue/proposals-draft-${DATE}.txt \
    and write each individual proposal to a separate file \
    named ~/proposals/queue/proposal-${DATE}-001.txt through \
    ~/proposals/queue/proposal-${DATE}-NNN.txt"

    # Narrate summary
    apex "use espeak to say proposals generated and ready for review in proposals queue"

    echo "[${DATE} ${TIME}] Proposals generated." >> ~/proposals/logs/scan.log
}

# ── APPROVE PROPOSAL ──────────────────────────────────────
approve_proposal() {
    FILE=$2
    cp ~/proposals/queue/${FILE} ~/proposals/approved/${FILE}
    apex "append ${FILE} approved ${DATE} ${TIME} to ~/proposals/logs/approval-log.txt"
    apex "use espeak to say proposal ${FILE} approved and moved to send queue"
}

# ── LOG OUTCOME ───────────────────────────────────────────
log_outcome() {
    FILE=$2
    OUTCOME=$3   # won or lost
    VALUE=$4     # contract value if won

    cp ~/proposals/sent/${FILE} ~/proposals/${OUTCOME}/${FILE}

    apex "append outcome ${OUTCOME} file ${FILE} value ${VALUE} date ${DATE} \
    to ~/proposals/logs/outcome-log.txt"

    apex "save proposal outcome to apex memory as latest_outcome \
    with value ${OUTCOME} ${VALUE} ${DATE}"
}

# ── WEEKLY PERFORMANCE REPORT ─────────────────────────────
weekly_report() {
    apex "read ~/proposals/logs/outcome-log.txt \
    and ~/proposals/logs/approval-log.txt \
    and calculate proposals generated this week approved sent won lost \
    total pipeline value and win rate \
    and write performance report to ~/proposals/reports/weekly-${DATE}.txt"

    apex "read ~/proposals/reports/weekly-${DATE}.txt \
    and use espeak in a confident business voice at speed 140 \
    and save to ~/proposals/reports/weekly-${DATE}.wav"

    aplay ~/proposals/reports/weekly-${DATE}.wav 2>/dev/null
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    scan)     scan_jobs ;;
    approve)  approve_proposal "$@" ;;
    outcome)  log_outcome "$@" ;;
    weekly)   weekly_report ;;
    *)        echo "Unknown command: $CMD" ;;
esac
