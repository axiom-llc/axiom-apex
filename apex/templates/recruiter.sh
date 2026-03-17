#!/usr/bin/env bash
# ============================================================
# recruiter.sh — Autonomous candidate screening and outreach
# Requires: apex
# Usage:    ./recruiter.sh "job_description_file" "resumes_dir" [top_n]
# Example:  ./recruiter.sh ~/jobs/backend-eng.txt ~/resumes/ 5
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

JD_FILE="${1:-}"
RESUME_DIR="${2:-}"
TOP_N="${3:-5}"
DATE=$(date +%Y-%m-%d_%H%M%S)
mkdir -p ~/recruiter/{scores,outreach,flags,reports,logs}

if [[ -z "$JD_FILE" || -z "$RESUME_DIR" ]]; then
    echo "Usage: $0 job_description.txt resumes_dir/ [top_n]"
    exit 1
fi

[[ ! -f "$JD_FILE" ]] && echo "✗ JD file not found: $JD_FILE" && exit 1
[[ ! -d "$RESUME_DIR" ]] && echo "✗ Resume dir not found: $RESUME_DIR" && exit 1

RESUMES=($(find "$RESUME_DIR" -maxdepth 1 -type f \( -name "*.txt" -o -name "*.md" -o -name "*.pdf" \)))
TOTAL=${#RESUMES[@]}

echo "▶ Job description : $JD_FILE"
echo "▶ Resumes found   : $TOTAL"
echo "▶ Top N           : $TOP_N"
echo ""

# ── PHASE 1: JD ANALYSIS ──────────────────────────────────
echo "── Analysing job description..."

apex "read the job description at ${JD_FILE} using read_file \
extract and write to ~/recruiter/reports/jd_analysis-${DATE}.txt: \
MUST-HAVE: non-negotiable requirements (skills, experience, credentials) \
NICE-TO-HAVE: preferred but not required \
DISQUALIFIERS: anything that should immediately rule out a candidate \
CULTURE SIGNALS: what kind of person thrives in this role \
COMPENSATION SIGNALS: any implied seniority or pay range \
SCORING RUBRIC: 10 specific criteria with weights summing to 100"

# ── PHASE 2: PARALLEL RESUME SCORING ──────────────────────
echo "── Scoring ${TOTAL} resumes in parallel..."

PIDS=()
for resume in "${RESUMES[@]}"; do
    name=$(basename "$resume" | sed 's/\.[^.]*$//')
    (
        apex "read the job analysis at ~/recruiter/reports/jd_analysis-${DATE}.txt \
        and read the resume at ${resume} using read_file \
        score the candidate using the 10-criteria rubric, show per-criterion scores \
        flag any must-have gaps as DISQUALIFIED \
        flag any red flags (gaps, vague claims, mismatch) \
        write a structured score card to ~/recruiter/scores/${name}-${DATE}.txt"
    ) &
    PIDS+=($!)
done

for pid in "${PIDS[@]}"; do
    wait "$pid" || true
done

echo "   ✓ all resumes scored"

# ── PHASE 3: RANKING + DISQUALIFICATION ───────────────────
echo "── Ranking candidates..."

apex "read all score cards in ~/recruiter/scores/ that contain ${DATE} using read_file \
rank all candidates by total score, highest first \
list disqualified candidates separately with the specific disqualifying reason \
write ranked list to ~/recruiter/reports/ranking-${DATE}.txt \
write disqualified list to ~/recruiter/flags/disqualified-${DATE}.txt"

# ── PHASE 4: TOP N OUTREACH (parallel) ────────────────────
echo "── Generating outreach for top ${TOP_N} candidates..."

apex "read ~/recruiter/reports/ranking-${DATE}.txt using read_file \
identify the top ${TOP_N} candidate names from the ranked list \
write their names one per line to ~/recruiter/reports/shortlist-${DATE}.txt"

# Generate outreach for top candidates in parallel
i=0
while IFS= read -r candidate && [[ $i -lt $TOP_N ]]; do
    [[ -z "$candidate" ]] && continue
    score_file=$(find ~/recruiter/scores/ -name "${candidate}-${DATE}.txt" 2>/dev/null | head -1)
    [[ -z "$score_file" ]] && i=$((i+1)) && continue

    (
        apex "read the job description at ${JD_FILE} using read_file \
        read the candidate score card at ${score_file} using read_file \
        write a personalised outreach message that: \
        references 1-2 specific things from their background, \
        is under 120 words, \
        sounds human not templated, \
        ends with a single low-friction CTA (15-min call) \
        write subject line + body to ~/recruiter/outreach/${candidate}-${DATE}.txt"
    ) &

    i=$((i+1))
done < ~/recruiter/reports/shortlist-${DATE}.txt

wait
echo "   ✓ outreach generated"

# ── PHASE 5: FINAL REPORT ─────────────────────────────────
apex "read the following using read_file: \
~/recruiter/reports/jd_analysis-${DATE}.txt \
~/recruiter/reports/ranking-${DATE}.txt \
~/recruiter/flags/disqualified-${DATE}.txt \
write a hiring manager report with sections: \
SHORTLIST (top ${TOP_N} with 2-line summary each) | \
DISQUALIFIED (count and common failure modes) | \
PIPELINE QUALITY (overall assessment of this candidate pool) | \
RECOMMENDATION (hire / expand search / revise JD) \
write to ~/recruiter/reports/REPORT-${DATE}.txt"

echo ""
cat ~/recruiter/reports/REPORT-${DATE}.txt
echo ""
echo "  Scores    : ~/recruiter/scores/"
echo "  Outreach  : ~/recruiter/outreach/"
echo "  Report    : ~/recruiter/reports/REPORT-${DATE}.txt"
