#!/usr/bin/env bash
# postmortem.sh — AI-driven incident post-mortem document generator
# Ingests logs, timeline events, and symptoms → produces blameless post-mortem
# Demonstrates: structured document synthesis, root cause analysis, iterative refinement
# Usage: ./postmortem.sh <incident_dir>
# Expected in incident_dir: logs/ (any .log or .txt), timeline.txt (optional), symptoms.txt (optional)
# Example: ./postmortem.sh ~/incidents/2025-03-01-api-outage

set -euo pipefail

INCIDENT_DIR="${1:-}"

if [[ -z "$INCIDENT_DIR" || ! -d "$INCIDENT_DIR" ]]; then
    echo "Usage: $0 <incident_dir>"
    echo ""
    echo "Scaffold a new incident directory:"
    echo "  mkdir -p ~/incidents/my-incident/logs"
    echo "  echo 'Service became unresponsive at 14:32 UTC' > ~/incidents/my-incident/symptoms.txt"
    echo "  echo '14:30 Deployment pushed to prod' > ~/incidents/my-incident/timeline.txt"
    exit 1
fi

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="$HOME/postmortem/$(date +%Y%m%d_%H%M%S)"
INCIDENT_NAME=$(basename "$INCIDENT_DIR")

EVIDENCE="$OUTDIR/evidence.txt"
ANALYSIS="$OUTDIR/analysis.txt"
TIMELINE_OUT="$OUTDIR/timeline_reconstructed.txt"
POSTMORTEM="$OUTDIR/postmortem.md"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Incident : $INCIDENT_NAME"
echo "▶ Source   : $INCIDENT_DIR"
echo "▶ Output   : $OUTDIR"
echo ""

espeak-ng "Starting post-mortem analysis for incident: $(echo "$INCIDENT_NAME" | tr '-' ' ')" 2>/dev/null || true

# ── Ingest evidence ───────────────────────────────────────────────────────────
echo "── Ingesting evidence..."
> "$EVIDENCE"

LOG_COUNT=0
while IFS= read -r -d '' LOGFILE; do
    LOGNAME=$(basename "$LOGFILE")
    echo "=== LOG: $LOGNAME ===" >> "$EVIDENCE"
    # Tail to avoid context overflow on large logs
    tail -500 "$LOGFILE" >> "$EVIDENCE"
    echo "" >> "$EVIDENCE"
    LOG_COUNT=$((LOG_COUNT + 1))
    echo "   + $LOGNAME"
done < <(find "$INCIDENT_DIR/logs" -type f \( -name "*.log" -o -name "*.txt" \) -print0 2>/dev/null)

if [[ -f "$INCIDENT_DIR/timeline.txt" ]]; then
    echo "=== PROVIDED TIMELINE ===" >> "$EVIDENCE"
    cat "$INCIDENT_DIR/timeline.txt" >> "$EVIDENCE"
    echo "" >> "$EVIDENCE"
    echo "   + timeline.txt"
fi

if [[ -f "$INCIDENT_DIR/symptoms.txt" ]]; then
    echo "=== REPORTED SYMPTOMS ===" >> "$EVIDENCE"
    cat "$INCIDENT_DIR/symptoms.txt" >> "$EVIDENCE"
    echo "" >> "$EVIDENCE"
    echo "   + symptoms.txt"
fi

if [[ -f "$INCIDENT_DIR/notes.txt" ]]; then
    echo "=== RESPONDER NOTES ===" >> "$EVIDENCE"
    cat "$INCIDENT_DIR/notes.txt" >> "$EVIDENCE"
    echo "" >> "$EVIDENCE"
    echo "   + notes.txt"
fi

echo "   ✓ $LOG_COUNT log file(s) ingested"

# ── Timeline reconstruction ───────────────────────────────────────────────────
echo ""
echo "── Reconstructing timeline..."

apex "You are a site reliability engineer performing post-mortem analysis.

Read the evidence file using read_file from ${EVIDENCE}

Reconstruct a precise chronological timeline of this incident.
For each event:
TIME    : exact timestamp if available, estimated if not (mark estimated with ~)
EVENT   : what happened (system state change, alert, human action, symptom)
SOURCE  : which log or input this came from
IMPACT  : user/system impact at this moment (none/degraded/outage)

Format as a clean table. Order strictly by time.
After the table, write a 2-sentence narrative of the incident arc.

Write to ${TIMELINE_OUT} using write_file"

[[ -f "$TIMELINE_OUT" ]] && echo "   ✓ timeline reconstructed" || echo "   ⚠ timeline reconstruction failed"

# ── Root cause analysis ───────────────────────────────────────────────────────
echo ""
echo "── Running root cause analysis..."

apex "You are performing blameless root cause analysis on a production incident.

Read the evidence from ${EVIDENCE} using read_file.
Read the reconstructed timeline from ${TIMELINE_OUT} using read_file.

Apply the 5 Whys method to identify the root cause chain.
Then classify the root cause into one of:
- human error       : incorrect action or decision
- process gap       : missing procedure or unclear ownership
- configuration     : misconfiguration or bad default
- code defect       : software bug or race condition
- infrastructure    : capacity, hardware, or dependency failure
- unknown           : insufficient evidence

Output:
ROOT_CAUSE_CLASS: <class>
ROOT_CAUSE: <one precise sentence>

5 WHYS CHAIN:
Why 1: [symptom] → because [cause 1]
Why 2: [cause 1] → because [cause 2]
Why 3: [cause 2] → because [cause 3]
Why 4: [cause 3] → because [cause 4]
Why 5: [cause 4] → because [root cause]

CONTRIBUTING_FACTORS:
- [factor 1]
- [factor 2]
(list systemic conditions that made this incident possible or worse)

Write to ${ANALYSIS} using write_file"

[[ -f "$ANALYSIS" ]] && echo "   ✓ root cause analysed" || echo "   ⚠ analysis failed"

# ── Post-mortem document ──────────────────────────────────────────────────────
echo ""
echo "── Writing post-mortem document..."

SEVERITY_LEVELS=("SEV1 (critical, full outage)" "SEV2 (major degradation)" "SEV3 (partial impact)" "SEV4 (minor, no user impact)")

apex "You are writing a blameless post-mortem for an engineering team.

Read the following using read_file:
- Evidence    : ${EVIDENCE}
- Timeline    : ${TIMELINE_OUT}
- RCA         : ${ANALYSIS}

Produce a complete post-mortem document in Markdown:

# Post-Mortem: $INCIDENT_NAME
**Date:** $(date +%Y-%m-%d)
**Status:** Draft

## Impact
(who was affected, for how long, at what scale — be specific with numbers if available)

## Severity
(classify as: ${SEVERITY_LEVELS[*]})

## Timeline
(reproduce the reconstructed timeline table)

## Root Cause
(the 5-whys chain and root cause classification from the analysis)

## Contributing Factors
(systemic issues that enabled this incident)

## What Went Well
(detection speed, response quality, communications, tooling that helped)

## What Went Wrong
(delayed detection, unclear runbooks, missing monitoring, coordination failures)

## Action Items
(table: Priority | Owner | Action | Due Date)
- At minimum: one fix for root cause, one monitoring improvement, one process change
- Priority: P1 (this week) / P2 (this sprint) / P3 (this quarter)
- Owner: team or role, not individual
- Due Date: relative (e.g. 'within 7 days')

## Lessons Learned
(3 concrete takeaways applicable beyond this incident)

Tone: blameless, technical, direct. No speculation beyond evidence.
Write to ${POSTMORTEM} using write_file"

echo ""
echo "✓ Done"
echo "  Evidence    : $EVIDENCE"
echo "  Timeline    : $TIMELINE_OUT"
echo "  Analysis    : $ANALYSIS"
echo "  Post-mortem : $POSTMORTEM"

espeak-ng "Post-mortem complete. Document written to: postmortem dot m d" 2>/dev/null || true
