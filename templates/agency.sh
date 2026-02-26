#!/usr/bin/env bash
# ============================================================
# APEX INTEGRATION TEMPLATE — FREELANCE CREATIVE AGENCY
# Version: 1.0
# Axiom LLC
# ============================================================
# DIRECTORY STRUCTURE:
#   ~/agency/
#     clients/          # Client profiles and briefs
#     projects/         # Active project files
#     briefs/           # Creative briefs and deliverables
#     copy/             # Generated copy, scripts, content
#     proposals/        # Project proposals and quotes
#     invoices/         # Billing and payment tracking
#     reports/          # Agency performance reports
#     audio/            # Narrated briefings
#     logs/             # Script execution logs
# ============================================================
# CRON SCHEDULE:
#   0 8  * * 1-5   ./apex-agency.sh morning
#   0 17 * * 1-5   ./apex-agency.sh eod
#   0 9  * * 1     ./apex-agency.sh weekly
#   0 10 1 * *     ./apex-agency.sh invoice-all
# ============================================================

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
WEEK=$(date +%V)
MONTH=$(date +%B)
AGENCY="[Agency Name]"

mkdir -p ~/agency/{clients,projects,briefs,copy,proposals,invoices,reports,audio,logs}

CMD=${1:-morning}

# ── MORNING BRIEF ─────────────────────────────────────────
morning_brief() {
    apex "read all project files in ~/agency/projects \
    and identify any deadlines within the next 3 days \
    and write urgency alerts to ~/agency/reports/urgent-${DATE}.txt" &

    apex "read all client files in ~/agency/clients \
    and identify any awaiting feedback or approval \
    and write to ~/agency/reports/awaiting-${DATE}.txt" &

    wait

    apex "read ~/agency/reports/urgent-${DATE}.txt \
    ~/agency/reports/awaiting-${DATE}.txt \
    and write a structured ${DAY} morning creative brief for ${AGENCY} \
    with sections for urgent deadlines awaiting client feedback \
    and today's production priorities \
    to ~/agency/reports/morning-brief-${DATE}.txt"

    apex "read ~/agency/reports/morning-brief-${DATE}.txt \
    and use espeak in a creative director voice at speed 145 \
    and save to ~/agency/audio/morning-brief-${DATE}.wav"

    aplay ~/agency/audio/morning-brief-${DATE}.wav 2>/dev/null
}

# ── NEW PROJECT INTAKE ────────────────────────────────────
new_project() {
    CLIENT=$2
    PROJECT=$3
    TYPE=$4        # branding, web, social, campaign, video
    BUDGET=$5
    DEADLINE=$6
    SLUG=$(echo "${CLIENT}-${PROJECT}" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

    mkdir -p ~/agency/projects/${SLUG}

    apex "write a new project brief for client ${CLIENT} \
    project ${PROJECT} type ${TYPE} budget ${BUDGET} \
    deadline ${DEADLINE} opened ${DATE} status ACTIVE \
    with sections for objectives deliverables timeline and notes \
    to ~/agency/projects/${SLUG}/brief.txt"

    # Auto-generate project proposal
    apex "read ~/agency/projects/${SLUG}/brief.txt \
    and write a professional project proposal for client ${CLIENT} \
    for ${TYPE} project ${PROJECT} \
    covering scope deliverables timeline investment and terms \
    to ~/agency/proposals/${SLUG}-proposal.txt"

    # Project kick-off email draft
    apex "write a professional project kick-off email to client ${CLIENT} \
    for project ${PROJECT} covering next steps requirements needed \
    and first milestone date \
    to ~/agency/copy/${SLUG}-kickoff-email.txt"

    apex "use espeak to say new project opened: ${PROJECT} for ${CLIENT}"
    echo "[${DATE}] New project: ${SLUG}" >> ~/agency/logs/projects.log
}

# ── GENERATE CREATIVE COPY ────────────────────────────────
generate_copy() {
    SLUG=$2
    TYPE=$3        # headline, tagline, social, email, script, press-release
    BRIEF=$4

    apex "read ~/agency/projects/${SLUG}/brief.txt \
    and write 5 creative ${TYPE} variations \
    based on brief: ${BRIEF} \
    in the brand voice of the client \
    to ~/agency/copy/${SLUG}-${TYPE}-${DATE}.txt"

    apex "read ~/agency/copy/${SLUG}-${TYPE}-${DATE}.txt \
    and use espeak in a confident creative director voice at speed 140 \
    and save to ~/agency/audio/${SLUG}-${TYPE}-${DATE}.wav"

    aplay ~/agency/audio/${SLUG}-${TYPE}-${DATE}.wav 2>/dev/null
}

# ── GENERATE SOCIAL CONTENT PACK ─────────────────────────
social_pack() {
    SLUG=$2
    CAMPAIGN=$3
    PLATFORMS=$4   # "instagram facebook linkedin twitter"

    apex "read ~/agency/projects/${SLUG}/brief.txt \
    and write a full social media content pack for campaign ${CAMPAIGN} \
    covering ${PLATFORMS} \
    with 7 days of posts per platform \
    tailored tone and format per platform \
    to ~/agency/copy/${SLUG}-social-pack-${DATE}.txt"

    apex "use espeak to say social content pack generated for ${SLUG} campaign ${CAMPAIGN}"
}

# ── LOG MILESTONE ─────────────────────────────────────────
log_milestone() {
    SLUG=$2
    MILESTONE=$3
    STATUS=$4      # COMPLETE, PENDING, BLOCKED

    apex "append milestone ${MILESTONE} status ${STATUS} date ${DATE} \
    to ~/agency/projects/${SLUG}/milestones.txt"

    if [ "$STATUS" = "COMPLETE" ]; then
        apex "use espeak to say milestone complete: ${MILESTONE} on project ${SLUG}"
    elif [ "$STATUS" = "BLOCKED" ]; then
        apex "use espeak to say warning: milestone ${MILESTONE} is blocked on ${SLUG}"
    fi
}

# ── EOD SUMMARY ───────────────────────────────────────────
end_of_day() {
    apex "read all project files and milestone logs in ~/agency/projects \
    and write an end of day production summary for ${DATE} \
    covering work completed in progress and blocked \
    to ~/agency/reports/eod-${DATE}.txt"

    apex "read ~/agency/reports/eod-${DATE}.txt \
    and use espeak at speed 135 \
    and save to ~/agency/audio/eod-${DATE}.wav"

    aplay ~/agency/audio/eod-${DATE}.wav 2>/dev/null
}

# ── WEEKLY REVIEW ─────────────────────────────────────────
weekly_review() {
    apex "read all project files in ~/agency/projects \
    and generate a weekly project health report for week ${WEEK} \
    showing each project status milestones hit missed \
    days to deadline and risk level \
    to ~/agency/reports/weekly-projects-${DATE}.txt" &

    apex "read ~/agency/invoices \
    and calculate invoiced amount paid outstanding \
    and revenue forecast for the month \
    to ~/agency/reports/weekly-revenue-${DATE}.txt" &

    wait

    apex "read ~/agency/reports/weekly-projects-${DATE}.txt \
    ~/agency/reports/weekly-revenue-${DATE}.txt \
    and write a comprehensive weekly agency review for ${AGENCY} week ${WEEK} \
    with project health revenue pipeline and team priorities \
    to ~/agency/reports/weekly-review-${DATE}.txt"

    apex "read ~/agency/reports/weekly-review-${DATE}.txt \
    and use espeak in David Ogilvy's voice at speed 135 \
    and save to ~/agency/audio/weekly-review-${DATE}.wav"

    aplay ~/agency/audio/weekly-review-${DATE}.wav 2>/dev/null
}

# ── INVOICE ALL COMPLETED PROJECTS ────────────────────────
invoice_all() {
    for project_dir in ~/agency/projects/*/; do
        SLUG=$(basename "$project_dir")
        [ -f "${project_dir}brief.txt" ] || continue

        source <(grep -E '^(CLIENT|PROJECT|BUDGET):' "${project_dir}brief.txt" \
                 | sed 's/: /="/' | sed 's/$/"/')

        INVOICE_NUM="INV-${SLUG^^}-$(date +%Y%m)"

        apex "write a professional invoice numbered ${INVOICE_NUM} \
        from ${AGENCY} \
        to client ${CLIENT} \
        for project ${PROJECT} services rendered ${MONTH} \
        amount ${BUDGET} \
        due 30 days from ${DATE} \
        to ~/agency/invoices/${INVOICE_NUM}.txt"
    done

    apex "use espeak to say all invoices generated for ${MONTH}"
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)        morning_brief ;;
    new-project)    new_project "$@" ;;
    copy)           generate_copy "$@" ;;
    social-pack)    social_pack "$@" ;;
    milestone)      log_milestone "$@" ;;
    eod)            end_of_day ;;
    weekly)         weekly_review ;;
    invoice-all)    invoice_all ;;
    *)              echo "Unknown: $CMD" ;;
esac
