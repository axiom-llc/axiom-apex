#!/usr/bin/env bash
# ============================================================
# APEX INTEGRATION TEMPLATE — PERSONAL TRAINER / GYM
# Version: 1.0
# Axiom LLC
# ============================================================
# DIRECTORY STRUCTURE:
#   ~/fitness/
#     clients/          # One file per client with goals and history
#     programs/         # Generated workout programs
#     sessions/         # Logged session notes
#     nutrition/        # Nutrition plans and logs
#     progress/         # Client progress tracking
#     reports/          # Generated weekly/monthly reports
#     audio/            # Narrated briefings and programs
#     invoices/         # Client billing
#     logs/             # Script execution logs
# ============================================================
# CRON SCHEDULE:
#   0 6  * * 1-6   ./apex-fitness.sh morning
#   0 20 * * *     ./apex-fitness.sh evening-check
#   0 8  * * 1     ./apex-fitness.sh weekly-programs
#   0 9  1 * *     ./apex-fitness.sh invoice-all
# ============================================================

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
WEEK=$(date +%V)
MONTH=$(date +%B)
TRAINER="[Trainer Name]"

mkdir -p ~/fitness/{clients,programs,sessions,nutrition,progress,reports,audio,invoices,logs}

CMD=${1:-morning}

# ── MORNING BRIEF ─────────────────────────────────────────
morning_brief() {
    apex "read all client files in ~/fitness/clients \
    and extract all sessions scheduled for today ${DATE} \
    and write to ~/fitness/reports/todays-sessions-${DATE}.txt"

    apex "read ~/fitness/reports/todays-sessions-${DATE}.txt \
    and for each client today write a one-line session focus note \
    based on their program and last session log \
    to ~/fitness/reports/session-focus-${DATE}.txt"

    apex "read ~/fitness/reports/todays-sessions-${DATE}.txt \
    ~/fitness/reports/session-focus-${DATE}.txt \
    and write a ${DAY} morning brief for ${TRAINER} \
    covering all clients today their goals and session focus \
    to ~/fitness/reports/morning-brief-${DATE}.txt"

    apex "read ~/fitness/reports/morning-brief-${DATE}.txt \
    and use espeak in a motivational drill sergeant voice at speed 150 \
    and save to ~/fitness/audio/morning-brief-${DATE}.wav"

    aplay ~/fitness/audio/morning-brief-${DATE}.wav 2>/dev/null
}

# ── ONBOARD NEW CLIENT ────────────────────────────────────
new_client() {
    NAME=$2
    AGE=$3
    GOAL=$4         # weight-loss, muscle-gain, endurance, rehab
    LEVEL=$5        # beginner, intermediate, advanced
    RATE=$6
    SLUG=$(echo "$NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

    mkdir -p ~/fitness/clients/${SLUG}

    apex "write a new client profile for ${NAME} age ${AGE} \
    fitness goal ${GOAL} level ${LEVEL} rate ${RATE} \
    start date ${DATE} with sections for goals \
    health notes exercise history and preferences \
    to ~/fitness/clients/${SLUG}/profile.txt"

    # Generate initial 4-week program
    apex "read ~/fitness/clients/${SLUG}/profile.txt \
    and write a complete 4-week progressive training program \
    tailored to ${NAME} age ${AGE} goal ${GOAL} level ${LEVEL} \
    with weekly breakdown daily sessions sets reps and rest periods \
    to ~/fitness/programs/${SLUG}-program-week01-04.txt"

    # Generate nutrition plan
    apex "read ~/fitness/clients/${SLUG}/profile.txt \
    and write a practical nutrition plan for ${NAME} \
    aligned with ${GOAL} including daily calorie target \
    macronutrient splits meal timing and example meals \
    to ~/fitness/nutrition/${SLUG}-nutrition.txt"

    # Narrate program for client
    apex "read ~/fitness/programs/${SLUG}-program-week01-04.txt \
    and use espeak in a professional trainer voice at speed 140 \
    and save to ~/fitness/audio/${SLUG}-program-intro.wav"

    apex "use espeak to say new client ${NAME} onboarded program and nutrition plan generated"
    echo "[${DATE}] New client: ${SLUG}" >> ~/fitness/logs/clients.log
}

# ── LOG SESSION ───────────────────────────────────────────
log_session() {
    SLUG=$2
    EXERCISES=$3   # "squats 5x5, bench 4x8, deadlift 3x5"
    NOTES=$4

    apex "append session log for ${SLUG} date ${DATE} \
    exercises: ${EXERCISES} notes: ${NOTES} \
    to ~/fitness/sessions/${SLUG}-sessions.txt"

    apex "read ~/fitness/sessions/${SLUG}-sessions.txt \
    ~/fitness/clients/${SLUG}/profile.txt \
    and write a brief session analysis noting progress \
    areas of improvement and next session focus \
    to ~/fitness/sessions/${SLUG}-analysis-${DATE}.txt"

    apex "use espeak to say session logged for ${SLUG}"
}

# ── PROGRESS CHECK ────────────────────────────────────────
progress_check() {
    SLUG=$2
    WEIGHT=$3
    MEASUREMENTS=$4   # "chest:42 waist:34 hips:38"

    apex "append progress entry for date ${DATE} \
    weight ${WEIGHT} measurements ${MEASUREMENTS} \
    to ~/fitness/progress/${SLUG}-progress.txt"

    apex "read ~/fitness/progress/${SLUG}-progress.txt \
    ~/fitness/clients/${SLUG}/profile.txt \
    and write a progress analysis comparing current to starting stats \
    highlighting wins trends and adjustments needed \
    to ~/fitness/progress/${SLUG}-analysis-${DATE}.txt"

    apex "read ~/fitness/progress/${SLUG}-analysis-${DATE}.txt \
    and use espeak in an encouraging coach voice at speed 135 \
    and save to ~/fitness/audio/${SLUG}-progress-${DATE}.wav"

    aplay ~/fitness/audio/${SLUG}-progress-${DATE}.wav 2>/dev/null
}

# ── WEEKLY PROGRAM REFRESH ────────────────────────────────
weekly_programs() {
    for client_dir in ~/fitness/clients/*/; do
        SLUG=$(basename "$client_dir")
        [ -f "${client_dir}profile.txt" ] || continue

        (
            apex "read ~/fitness/clients/${SLUG}/profile.txt \
            ~/fitness/sessions/${SLUG}-sessions.txt \
            ~/fitness/progress/${SLUG}-progress.txt \
            and write an updated week ${WEEK} training program for ${SLUG} \
            incorporating recent session performance and progress data \
            with progressive overload adjustments \
            to ~/fitness/programs/${SLUG}-program-week${WEEK}.txt"

            apex "use espeak to say week ${WEEK} program generated for ${SLUG}"
        ) &
    done
    wait
    apex "use espeak to say all weekly programs refreshed for week ${WEEK}"
}

# ── EVENING CHECK — MISSED SESSIONS ──────────────────────
evening_check() {
    apex "read ~/fitness/reports/todays-sessions-${DATE}.txt \
    ~/fitness/sessions \
    and identify any clients scheduled today with no session logged \
    and write missed session alerts to ~/fitness/reports/missed-${DATE}.txt"

    MISSED=$(wc -l < ~/fitness/reports/missed-${DATE}.txt 2>/dev/null || echo 0)
    if [ "$MISSED" -gt 0 ]; then
        apex "use espeak to say ${MISSED} clients missed their session today"
    fi
}

# ── MONTHLY INVOICES ──────────────────────────────────────
invoice_all() {
    for client_dir in ~/fitness/clients/*/; do
        SLUG=$(basename "$client_dir")
        [ -f "${client_dir}profile.txt" ] || continue

        source <(grep -E '^(NAME|RATE):' "${client_dir}profile.txt" \
                 | sed 's/: /="/' | sed 's/$/"/')

        SESSION_COUNT=$(grep -c "${MONTH}" ~/fitness/sessions/${SLUG}-sessions.txt 2>/dev/null || echo 0)
        TOTAL=$(echo "$SESSION_COUNT * $RATE" | bc 2>/dev/null || echo "N/A")

        apex "write a professional invoice for client ${NAME} \
        for ${SESSION_COUNT} training sessions in ${MONTH} \
        at rate ${RATE} per session total ${TOTAL} \
        from trainer ${TRAINER} dated ${DATE} \
        to ~/fitness/invoices/${SLUG}-${MONTH}.txt"
    done

    apex "use espeak to say all invoices generated for ${MONTH}"
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)        morning_brief ;;
    new-client)     new_client "$@" ;;
    log-session)    log_session "$@" ;;
    progress)       progress_check "$@" ;;
    weekly-programs) weekly_programs ;;
    evening-check)  evening_check ;;
    invoice-all)    invoice_all ;;
    *)              echo "Unknown: $CMD" ;;
esac
