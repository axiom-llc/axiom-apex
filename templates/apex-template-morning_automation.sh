#!/bin/bash
# ============================================================
# APEX MORNING AUTOMATION — ~2 hours compressed to runtime
# ============================================================

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
mkdir -p ~/morning/{briefs,audio,journal,tasks}

# ── PHASE 1: ENVIRONMENT SNAPSHOT (parallel) ──────────────
apex "get date time hostname uptime kernel cpu load and write to ~/morning/briefs/sysinfo.txt" &
apex "fetch https://wttr.in/$(cat ~/.config/city) using curl and write to ~/morning/briefs/weather.txt" &
apex "write top 10 memory and cpu processes to ~/morning/briefs/procs.txt" &
apex "get disk usage for all mounted filesystems and write to ~/morning/briefs/disk.txt" &
apex "fetch https://api.github.com/notifications using curl and write to ~/morning/briefs/gh-notifications.txt" &
wait

# ── PHASE 2: CONTENT GENERATION (parallel) ────────────────
apex "write a ${DAY} morning motivational message for a developer to ~/morning/briefs/motivation.txt" &
apex "write today's date as ${DATE} and generate a prioritized task list for a productive dev morning to ~/morning/tasks/today.txt" &
apex "fetch https://wttr.in/$(cat ~/.config/city) using curl extract clothing recommendation based on temperature to ~/morning/briefs/clothing.txt" &
wait

# ── PHASE 3: CONSOLIDATE BRIEF ────────────────────────────
apex "read all files in ~/morning/briefs and combine into a structured morning brief \
with sections for weather system health notifications and motivation \
to ~/morning/briefs/full-brief-${DATE}.txt"

# ── PHASE 4: AUDIO GENERATION (parallel) ──────────────────
apex "read ~/morning/briefs/weather.txt and use espeak in Morgan Freeman's voice \
at speed 140 and save to ~/morning/audio/weather.wav" &

apex "read ~/morning/briefs/motivation.txt and use espeak in David Attenborough's voice \
at speed 130 and save to ~/morning/audio/motivation.wav" &

apex "read ~/morning/tasks/today.txt and use espeak in a clear neutral voice \
at speed 145 and save to ~/morning/audio/tasks.wav" &

apex "read ~/morning/briefs/sysinfo.txt and use espeak in HAL 9000's voice \
at speed 120 and save to ~/morning/audio/sysinfo.wav" &
wait

# ── PHASE 5: FULL BRIEF NARRATION ─────────────────────────
apex "read ~/morning/briefs/full-brief-${DATE}.txt and use espeak in Morgan Freeman's voice \
at speed 135 pitch 35 and save to ~/morning/audio/full-brief-${DATE}.wav"

# ── PHASE 6: PLAY SEQUENCE ────────────────────────────────
aplay ~/morning/audio/weather.wav
aplay ~/morning/audio/sysinfo.wav
aplay ~/morning/audio/tasks.wav
aplay ~/morning/audio/motivation.wav

# ── PHASE 7: JOURNAL ENTRY ────────────────────────────────
apex "write a morning journal entry for ${DATE} ${DAY} incorporating weather \
system health and today's task priorities from files in ~/morning/briefs \
and ~/morning/tasks to ~/morning/journal/${DATE}.txt"

apex "use espeak in Morgan Freeman's voice to read ~/morning/journal/${DATE}.txt \
and save to ~/morning/audio/journal-${DATE}.wav"

# ── PHASE 8: ARCHIVE PREVIOUS DAY ────────────────────────
apex "archive all files in ~/morning older than 1 day into \
~/morning/archives/${DATE}-previous.tar.gz then use espeak to say morning routine complete"

# ── CRON SETUP ────────────────────────────────────────────
# Run at 7am daily:
# 0 7 * * * /home/u/scripts/morning.sh >> ~/morning/logs/morning.log 2>&1
