#!/usr/bin/env bash
# ============================================================
# therapist.sh — Structured journaling and pattern analysis agent
# Requires: apex
# Config:   echo "stoic" > ~/.config/apex/therapy_mode
# Modes:    stoic | cbt | ifs | somatic | existential
# Usage:    ./therapist.sh           # daily session
#           ./therapist.sh review    # weekly pattern review
#           ./therapist.sh crisis    # immediate grounding protocol
# ============================================================
set -euo pipefail

MODE_ARG="${1:-session}"
THERAPY_MODE=$(cat ~/.config/apex/therapy_mode 2>/dev/null || echo "cbt")
DATE=$(date +%Y-%m-%d)
WEEK=$(date +%Y-W%V)
TIME=$(date +%H:%M)
mkdir -p ~/therapy/{sessions,patterns,insights,reflections,logs}

# ── CRISIS MODE ────────────────────────────────────────────
if [[ "$MODE_ARG" == "crisis" ]]; then
    echo "── Grounding protocol initiated..."
    apex "the user is in distress and needs immediate grounding. \
    do not ask questions. do not analyse. \
    write a calm, structured grounding sequence: \
    5-4-3-2-1 sensory awareness, a breathing instruction, \
    one reframe that reduces catastrophising, \
    and a single small action they can take in the next 5 minutes. \
    write to ~/therapy/sessions/crisis-${DATE}-${TIME//:/-}.txt using write_file"
    cat ~/therapy/sessions/crisis-${DATE}-${TIME//:/-}.txt
    exit 0
fi

# ── WEEKLY REVIEW MODE ─────────────────────────────────────
if [[ "$MODE_ARG" == "review" ]]; then
    echo "── Generating weekly pattern review for ${WEEK}..."

    SESSIONS=($(find ~/therapy/sessions/ -name "${DATE:0:7}*.txt" -not -name "crisis*" | sort))
    TOTAL=${#SESSIONS[@]}

    if [[ $TOTAL -eq 0 ]]; then
        echo "No sessions found for this month."
        exit 0
    fi

    apex "read the following session files using read_file: ${SESSIONS[*]} \
    using the ${THERAPY_MODE} therapeutic framework \
    produce a weekly pattern analysis: \
    RECURRING THEMES: topics, people, or situations that keep appearing \
    COGNITIVE PATTERNS: thinking distortions or patterns that recurred (label with CBT names if applicable) \
    EMOTIONAL TRENDS: mood arc over the period, triggers, regulation patterns \
    GROWTH SIGNALS: evidence of progress, changed perspective, successful coping \
    STUCK POINTS: areas showing no movement or active avoidance \
    RECOMMENDED FOCUS: one thing to work on in the coming week, with a specific practice \
    write to ~/therapy/patterns/week-${WEEK}.md using write_file"

    cat ~/therapy/patterns/week-${WEEK}.md
    echo ""
    echo "  Pattern file : ~/therapy/patterns/week-${WEEK}.md"
    exit 0
fi

# ── DAILY SESSION MODE ─────────────────────────────────────
SESSION_FILE=~/therapy/sessions/session-${DATE}.txt
PREV_SESSIONS=($(find ~/therapy/sessions/ -name "session-*.txt" | sort -r | head -5))

echo "── Starting ${THERAPY_MODE} session for ${DATE}..."

# Load context from recent sessions
CONTEXT_NOTE=""
if [[ ${#PREV_SESSIONS[@]} -gt 0 ]]; then
    apex "read these recent session files using read_file: ${PREV_SESSIONS[*]} \
    extract: \
    open threads (things mentioned but not resolved), \
    last stated mood or energy level, \
    any commitments or intentions the person made \
    write to ~/therapy/sessions/context-${DATE}.txt using write_file"
    CONTEXT_NOTE=$(cat ~/therapy/sessions/context-${DATE}.txt 2>/dev/null || echo "")
fi

# ── PHASE 1: OPENING CHECK-IN ─────────────────────────────
apex "you are a ${THERAPY_MODE}-informed journaling companion. \
today is ${DATE} at ${TIME}. \
${CONTEXT_NOTE:+recent context: ${CONTEXT_NOTE}} \
open the session with: \
1. a single specific check-in question that references something from recent sessions if available, \
   or a clean opening question if this is the first session \
2. a mood rating prompt: ask them to rate energy and mood 1-10 \
do not lecture. do not give advice yet. just open the space. \
write to ~/therapy/sessions/opening-${DATE}.txt using write_file"

echo ""
cat ~/therapy/sessions/opening-${DATE}.txt
echo ""
echo "── Respond below (Ctrl+D when done):"
USER_RESPONSE=$(cat)

echo "$USER_RESPONSE" > ~/therapy/sessions/response-${DATE}.txt

# ── PHASE 2: REFLECTION + INQUIRY ─────────────────────────
apex "you are a ${THERAPY_MODE}-informed journaling companion. \
read the opening questions from ~/therapy/sessions/opening-${DATE}.txt using read_file \
read the user's response from ~/therapy/sessions/response-${DATE}.txt using read_file \
${CONTEXT_NOTE:+prior context: ${CONTEXT_NOTE}} \
your task: \
1. reflect back what you heard in 1-2 sentences — accurate, not interpretive \
2. identify the single most emotionally significant element in their response \
3. ask one follow-up question that goes deeper on that element \
do not ask multiple questions. do not give advice. hold the space. \
write to ~/therapy/sessions/reflection-${DATE}.txt using write_file"

echo ""
cat ~/therapy/sessions/reflection-${DATE}.txt
echo ""
echo "── Continue (Ctrl+D when done):"
USER_RESPONSE2=$(cat)
echo "$USER_RESPONSE2" >> ~/therapy/sessions/response-${DATE}.txt

# ── PHASE 3: INSIGHT + CLOSE ──────────────────────────────
apex "you are a ${THERAPY_MODE}-informed journaling companion. \
read the full session exchange from: \
~/therapy/sessions/opening-${DATE}.txt \
~/therapy/sessions/reflection-${DATE}.txt \
~/therapy/sessions/response-${DATE}.txt using read_file \
close the session with: \
1. name what you observe — a pattern, a tension, a strength — one thing, specific \
2. offer one reframe or insight grounded in ${THERAPY_MODE} principles \
3. suggest one small, concrete practice for the next 24 hours \
4. end with a single closing question they can sit with — not answer now \
tone: warm, direct, non-patronising. no toxic positivity. \
write to ~/therapy/sessions/close-${DATE}.txt using write_file"

echo ""
cat ~/therapy/sessions/close-${DATE}.txt

# ── PHASE 4: SESSION RECORD ───────────────────────────────
apex "read all session files for today using read_file: \
~/therapy/sessions/opening-${DATE}.txt \
~/therapy/sessions/response-${DATE}.txt \
~/therapy/sessions/reflection-${DATE}.txt \
~/therapy/sessions/close-${DATE}.txt \
write a structured session record to ${SESSION_FILE}: \
DATE | MOOD_RATING | KEY_THEMES | COGNITIVE_PATTERNS_OBSERVED | \
INSIGHT_OFFERED | PRACTICE_ASSIGNED | OPEN_THREADS \
this record feeds future sessions — be precise and clinical"

echo ""
echo "  Session saved : $SESSION_FILE"
echo "  Run 'review'  : $0 review"
