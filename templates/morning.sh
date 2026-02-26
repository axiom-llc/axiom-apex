#!/usr/bin/env bash
# ============================================================
# morning.sh — Dev morning brief, narrated, ~2min runtime
# Requires: apex, espeak, aplay
# Config:   echo "YourCity" > ~/.config/apex/city
# Cron:     0 7 * * * ~/path/to/morning.sh >> ~/morning/logs/morning.log 2>&1
# ============================================================
set -euo pipefail

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
CITY=$(cat ~/.config/apex/city 2>/dev/null || echo "New+York")

mkdir -p ~/morning/{briefs,audio,journal,tasks,logs,archives}

# ── PHASE 1: ENVIRONMENT SNAPSHOT (parallel) ──────────────
apex "get date time hostname uptime kernel and cpu load and write to ~/morning/briefs/sysinfo.txt" &
apex "fetch https://wttr.in/${CITY}?format=j1 using curl and write to ~/morning/briefs/weather.txt" &
apex "write top 10 processes by cpu and memory to ~/morning/briefs/procs.txt" &
apex "get disk usage for all mounted filesystems and write to ~/morning/briefs/disk.txt" &
wait

# ── PHASE 2: CONTENT GENERATION (parallel) ────────────────
apex "write a ${DAY} morning motivational message for a developer to ~/morning/briefs/motivation.txt" &
apex "write a prioritized task list for a productive dev ${DAY} to ~/morning/tasks/today.txt" &
apex "read ~/morning/briefs/weather.txt and write a one-line clothing recommendation to ~/morning/briefs/clothing.txt" &
wait

# ── PHASE 3: CONSOLIDATE BRIEF ────────────────────────────
apex "read all files in ~/morning/briefs and write a structured morning brief \
with sections for weather clothing system health and motivation \
to ~/morning/briefs/full-brief-${DATE}.txt"

# ── PHASE 4: AUDIO GENERATION (parallel) ──────────────────
apex "read ~/morning/briefs/weather.txt ~/morning/briefs/clothing.txt \
and use espeak in Morgan Freeman's voice at speed 140 \
and save to ~/morning/audio/weather.wav" &

apex "read ~/morning/briefs/sysinfo.txt \
and use espeak in HAL 9000's voice at speed 120 \
and save to ~/morning/audio/sysinfo.wav" &

apex "read ~/morning/tasks/today.txt \
and use espeak in a clear neutral voice at speed 145 \
and save to ~/morning/audio/tasks.wav" &

apex "read ~/morning/briefs/motivation.txt \
and use espeak in David Attenborough's voice at speed 130 \
and save to ~/morning/audio/motivation.wav" &
wait

# ── PHASE 5: PLAY SEQUENCE ────────────────────────────────
for wav in weather sysinfo tasks motivation; do
    [[ -f ~/morning/audio/${wav}.wav ]] && aplay ~/morning/audio/${wav}.wav
done

# ── PHASE 6: JOURNAL ENTRY ────────────────────────────────
apex "write a morning journal entry for ${DATE} ${DAY} \
incorporating weather system health and today's task priorities \
from files in ~/morning/briefs and ~/morning/tasks \
to ~/morning/journal/${DATE}.txt"

# ── PHASE 7: ARCHIVE PREVIOUS DAY ─────────────────────────
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
ARCHIVE=~/morning/archives/${YESTERDAY}.tar.gz
if [[ ! -f "$ARCHIVE" ]]; then
    find ~/morning/{briefs,audio,tasks,journal} \
        -maxdepth 1 -name "*${YESTERDAY}*" -print0 | \
        tar czf "$ARCHIVE" --null -T - 2>/dev/null && \
        echo "[${DATE}] archived: ${YESTERDAY}" || true
fi
