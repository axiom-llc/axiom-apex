#!/usr/bin/env bash
# ============================================================
# war-room.sh — Crisis response command centre
# Requires: apex
# Config:   echo "Axiom LLC" > ~/.config/apex/company_name
#           echo "cto@example.com,ceo@example.com" > ~/.config/apex/war_room_contacts
# Usage:    ./war-room.sh "incident description" [severity] [incident_dir]
# Severity: P0 (total outage) | P1 (major degradation) | P2 (partial impact)
# Example:  ./war-room.sh "payment processing down for all EU customers" P0
# ============================================================
set -euo pipefail

INCIDENT="${1:-}"
SEVERITY="${2:-P1}"
INCIDENT_DIR="${3:-}"
COMPANY=$(cat ~/.config/apex/company_name 2>/dev/null || echo "The Company")
CONTACTS=$(cat ~/.config/apex/war_room_contacts 2>/dev/null || echo "")
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M:%S)
SLUG=$(date +%Y%m%d_%H%M%S)
mkdir -p ~/war-room/${SLUG}/{comms,playbook,logs,timeline}

if [[ -z "$INCIDENT" ]]; then
    echo "Usage: $0 \"incident description\" [P0|P1|P2] [incident_dir]"
    exit 1
fi

OUTDIR=~/war-room/${SLUG}

echo "▶ Incident  : $INCIDENT"
echo "▶ Severity  : $SEVERITY"
echo "▶ Company   : $COMPANY"
echo "▶ Started   : $DATE $TIME"
echo "▶ War room  : $OUTDIR"
echo ""

# Record incident open
echo "${DATE} ${TIME} — WAR ROOM OPENED — ${SEVERITY}" > "$OUTDIR/timeline/timeline.txt"
echo "INCIDENT: ${INCIDENT}" >> "$OUTDIR/timeline/timeline.txt"

# Ingest any existing evidence
if [[ -n "$INCIDENT_DIR" && -d "$INCIDENT_DIR" ]]; then
    apex "read all files in ${INCIDENT_DIR} using read_file \
    extract and summarise all evidence: error messages, log snippets, metrics anomalies, \
    timeline of events with timestamps where available \
    write to ${OUTDIR}/timeline/evidence.txt using write_file"
fi

# ── PHASE 1: IMMEDIATE SITUATION ASSESSMENT ────────────────
echo "── [Immediate] Assessing situation..."

apex "you are the incident commander for ${COMPANY}. \
incident: ${INCIDENT} \
severity: ${SEVERITY} \
time declared: ${DATE} ${TIME} \
${INCIDENT_DIR:+read evidence from ${OUTDIR}/timeline/evidence.txt using read_file} \
produce an immediate situation assessment: \
BLAST RADIUS: who and what is affected, estimated scope \
LIKELY CAUSE HYPOTHESES: top 3 ordered by probability with rationale \
IMMEDIATE RISK: what gets worse if nothing is done in the next 15 minutes \
FIRST ACTIONS: the 3 most important things to do right now, in order \
write to ${OUTDIR}/playbook/situation.txt using write_file"

cat "$OUTDIR/playbook/situation.txt"
echo ""

# ── PHASE 2: PARALLEL RESPONSE PACKAGE ────────────────────
echo "── [Parallel] Generating full response package..."

apex "read ${OUTDIR}/playbook/situation.txt using read_file \
write a complete incident response playbook for ${SEVERITY} incident at ${COMPANY}: \
IMMEDIATE (0-15 min): exact steps, who owns each, what success looks like \
SHORT TERM (15-60 min): investigation steps, escalation triggers, rollback criteria \
MEDIUM TERM (1-4 hours): resolution path, monitoring requirements, stakeholder cadence \
LONG TERM (4+ hours): if unresolved, what changes — alternative mitigations, customer SLA triggers \
each step must have an owner role, not just a task \
write to ${OUTDIR}/playbook/PLAYBOOK.txt using write_file" &

apex "read ${OUTDIR}/playbook/situation.txt using read_file \
write internal communications for ${SEVERITY} incident: \
1. SLACK/TEAMS WAR ROOM OPENER — pin this message, under 100 words, \
   states: what, who is affected, severity, war room location, initial hypothesis, next update time \
2. ENGINEERING BRIDGE BRIEF — technical detail for responders, under 150 words \
3. EXECUTIVE NOTIFICATION — for C-suite, under 80 words, \
   business impact first, technical detail minimal, action being taken, ETA to next update \
write to ${OUTDIR}/comms/internal-comms.txt using write_file" &

apex "read ${OUTDIR}/playbook/situation.txt using read_file \
write external customer communications for a ${SEVERITY} incident at ${COMPANY}: \
1. STATUS PAGE UPDATE — 2 sentences max, factual, no speculation \
2. IN-APP BANNER — under 15 words \
3. CUSTOMER EMAIL (if P0) — subject line + body, \
   acknowledges impact, explains what is happening, sets expectation, ends with empathy \
   under 200 words, no technical jargon \
4. SOCIAL POST (if warranted) — under 280 characters \
tone across all: calm, honest, accountable — never defensive \
write to ${OUTDIR}/comms/external-comms.txt using write_file" &

apex "read ${OUTDIR}/playbook/situation.txt using read_file \
write a spokesperson brief for anyone speaking to press or escalated customers: \
APPROVED STATEMENTS: 3 things that can be said verbatim \
DO NOT SAY: 5 things that must not be said and why \
LIKELY QUESTIONS: top 5 questions with suggested responses \
ESCALATION TRIPWIRES: if asked X, immediately involve legal/PR \
write to ${OUTDIR}/comms/spokesperson.txt using write_file" &

wait

# ── PHASE 3: DECISION LOG TEMPLATE ────────────────────────
apex "write a live decision log template for the war room at ${COMPANY}: \
a structured document responders fill in as the incident progresses, \
capturing: timestamp, decision made, who made it, rationale, outcome \
pre-populate with the immediate actions from ${OUTDIR}/playbook/situation.txt using read_file \
write to ${OUTDIR}/playbook/decision-log.txt using write_file"

# ── PHASE 4: RESOLUTION CRITERIA ──────────────────────────
apex "read ${OUTDIR}/playbook/situation.txt using read_file \
define clear resolution criteria for this incident: \
RESOLVED: specific measurable conditions that must be true to declare resolved \
MONITORING PERIOD: what to watch, for how long, before standing down \
POST-INCIDENT: what triggers a postmortem, who owns it, deadline \
write to ${OUTDIR}/playbook/resolution-criteria.txt using write_file"

echo ""
echo "══════════════════════════════════════════"
echo "  WAR ROOM ACTIVE — ${SEVERITY} — ${COMPANY}"
echo "══════════════════════════════════════════"
echo ""
echo "  Playbook         : ${OUTDIR}/playbook/PLAYBOOK.txt"
echo "  Internal comms   : ${OUTDIR}/comms/internal-comms.txt"
echo "  External comms   : ${OUTDIR}/comms/external-comms.txt"
echo "  Spokesperson     : ${OUTDIR}/comms/spokesperson.txt"
echo "  Decision log     : ${OUTDIR}/playbook/decision-log.txt"
echo "  Resolution gates : ${OUTDIR}/playbook/resolution-criteria.txt"
echo ""
echo "  On resolution, run postmortem.sh against: ${OUTDIR}/"
