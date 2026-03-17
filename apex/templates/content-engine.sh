#!/usr/bin/env bash
# ============================================================
# content-engine.sh — Automated content marketing pipeline
# Requires: apex
# Config:   ~/.config/apex/content_brand   — brand/company name
#           ~/.config/apex/content_topics  — comma-separated topic clusters
#           ~/.config/apex/content_audience — target reader description
#           ~/.config/apex/content_tone    — writing tone (default: technical, direct)
# Cron:     0 6  * * 1    ./content-engine.sh weekly-plan
#           0 7  * * 1-5  ./content-engine.sh morning
#           0 9  * * 2-4  ./content-engine.sh draft
#           0 8  * * 5    ./content-engine.sh publish-queue
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

BRAND="${BRAND:-$(cat ~/.config/apex/content_brand 2>/dev/null || echo "Your Brand")}"
TOPICS=$(cat ~/.config/apex/content_topics 2>/dev/null || echo "AI,automation,productivity")
AUDIENCE=$(cat ~/.config/apex/content_audience 2>/dev/null || echo "technical founders and builders")
TONE=$(cat ~/.config/apex/content_tone 2>/dev/null || echo "technical, direct, no fluff")
DATE=$(date +%Y-%m-%d)
WEEK=$(date +%V)

mkdir -p ~/content/{signals,briefs,drafts,published,queue,reports,logs,archives}

CMD=${1:-morning}

# ── MORNING SIGNAL SCAN ───────────────────────────────────
morning() {
    log ~/content/logs/content.log "Morning signal scan..."

    # Parallel: trending topics + competitor content + keyword signals
    apex "fetch https://news.ycombinator.com/rss using http_get
    extract stories related to: ${TOPICS}
    identify which stories have highest engagement (comments, points)
    write to ~/content/signals/hn-${DATE}.txt" &

    apex "fetch https://www.producthunt.com/feed using http_get
    extract launched products related to: ${TOPICS}
    note positioning language and pain points they emphasise
    write to ~/content/signals/ph-${DATE}.txt" &

    apex "fetch https://api.hnpwa.com/v0/jobs/1.json using http_get
    extract job postings — identify skills and tools repeatedly demanded
    these are keyword signals for content
    write to ~/content/signals/jobs-${DATE}.txt" &

    wait

    apex "read ~/content/signals/hn-${DATE}.txt
    ~/content/signals/ph-${DATE}.txt
    ~/content/signals/jobs-${DATE}.txt using read_file
    write a morning content signal brief for ${BRAND}:
    TRENDING TOPICS: what the target audience (${AUDIENCE}) is reading and discussing today
    KEYWORD OPPORTUNITIES: search terms appearing in job posts and product descriptions
    CONTENT ANGLES: 3 specific article angles we could own based on today's signals
    COMPETITOR GAPS: topics with high engagement but weak existing content
    write to ~/content/reports/morning-signals-${DATE}.txt"

    cat ~/content/reports/morning-signals-${DATE}.txt
    log ~/content/logs/content.log "Morning scan complete."
}

# ── WEEKLY CONTENT PLAN ───────────────────────────────────
weekly_plan() {
    log ~/content/logs/content.log "Generating weekly content plan..."

    apex "fetch https://news.ycombinator.com/rss using http_get
    and https://www.producthunt.com/feed using http_get
    extract trending themes in: ${TOPICS}
    write raw signals to ~/content/signals/weekly-signals-${DATE}.txt" &

    apex "read ~/content/published/ using read_file
    identify topics already covered in the last 30 days
    write coverage map to ~/content/reports/coverage-${DATE}.txt" &

    wait

    apex "read ~/content/signals/weekly-signals-${DATE}.txt
    ~/content/reports/coverage-${DATE}.txt using read_file

    write a content plan for ${BRAND} for week ${WEEK}:
    TARGET AUDIENCE: ${AUDIENCE}
    TONE: ${TONE}
    TOPICS: ${TOPICS}

    Produce exactly 5 content briefs. For each:
    TITLE: specific, not generic
    FORMAT: blog post | tutorial | case study | listicle | opinion
    KEYWORD TARGET: primary search term this piece should rank for
    ANGLE: what makes this take original — what conventional wisdom does it challenge?
    OUTLINE: 5-7 section headers
    ESTIMATED IMPACT: why this will resonate with ${AUDIENCE}
    PRIORITY: 1 (publish first) to 5 (publish last)

    Avoid topics in the coverage map.
    Write to ~/content/briefs/weekly-plan-${WEEK}-${DATE}.txt"

    cat ~/content/briefs/weekly-plan-${WEEK}-${DATE}.txt
    log ~/content/logs/content.log "Weekly plan generated."
}

# ── DRAFT GENERATION ──────────────────────────────────────
draft() {
    BRIEF_FILE="${2:-$(ls ~/content/briefs/*.txt 2>/dev/null | tail -1)}"
    require_file "$BRIEF_FILE" "Usage: $0 draft [brief_file]"

    DRAFT_ID="DRAFT-$(date +%s)"
    SLUG=$(basename "$BRIEF_FILE" .txt)

    # Phase 1: research the topic
    apex "read ${BRIEF_FILE} using read_file
    extract the TITLE, KEYWORD TARGET, and ANGLE from the brief
    fetch relevant context: search HN for related discussions
    write research notes to ~/content/drafts/${DRAFT_ID}-research.txt" &

    wait

    # Phase 2: write the draft
    apex "read ${BRIEF_FILE} using read_file
    read ~/content/drafts/${DRAFT_ID}-research.txt using read_file

    Write a complete draft article for ${BRAND}.
    Audience: ${AUDIENCE}
    Tone: ${TONE}

    Requirements:
    - Follow the outline from the brief exactly
    - Open with a concrete problem statement, not a generic introduction
    - Every section must contain at least one specific example, data point, or code snippet
    - No passive voice, no 'it is worth noting', no 'in conclusion'
    - Target 800-1200 words
    - End with a single clear takeaway, not a list of summaries

    Write the complete draft to ~/content/drafts/${DRAFT_ID}-draft.txt"

    # Phase 3: SEO pass
    apex "read ~/content/drafts/${DRAFT_ID}-draft.txt using read_file
    read ${BRIEF_FILE} using read_file
    perform an SEO review:
    KEYWORD DENSITY: does the primary keyword appear naturally 3-5 times?
    TITLE TAG: suggest an optimised <60 char title
    META DESCRIPTION: write a 155 char meta description
    INTERNAL LINK OPPORTUNITIES: where would internal links fit naturally?
    READABILITY: flag any paragraphs over 5 sentences
    SCORE: 1-10 with specific improvements
    Write SEO report to ~/content/drafts/${DRAFT_ID}-seo.txt"

    echo ""
    echo "── Draft: ~/content/drafts/${DRAFT_ID}-draft.txt"
    echo "── SEO:   ~/content/drafts/${DRAFT_ID}-seo.txt"
    echo ""
    cat ~/content/drafts/${DRAFT_ID}-seo.txt

    log ~/content/logs/content.log "Draft ${DRAFT_ID} generated from ${BRIEF_FILE}."
}

# ── SEO SCORE AN EXISTING DRAFT ───────────────────────────
seo_score() {
    DRAFT_FILE="$2"
    require_file "$DRAFT_FILE" "Usage: $0 seo-score <draft_file>"

    apex "read ${DRAFT_FILE} using read_file
    perform comprehensive SEO analysis:
    KEYWORD OPPORTUNITIES: what terms does this piece naturally rank for?
    STRUCTURAL SEO: heading hierarchy, paragraph length, scanability
    TITLE OPTIONS: 3 alternative title variants with character counts
    META DESCRIPTION: optimal 155-char meta description
    FEATURED SNIPPET OPPORTUNITY: is there a question this piece answers directly?
    IMPROVEMENT PRIORITY: top 3 changes to make before publishing
    Write analysis to ~/content/reports/seo-$(basename ${DRAFT_FILE})-${DATE}.txt"

    cat ~/content/reports/seo-$(basename ${DRAFT_FILE})-${DATE}.txt
}

# ── PUBLISH QUEUE ─────────────────────────────────────────
publish_queue() {
    apex "read all draft files in ~/content/drafts that do not have a corresponding file in ~/content/published using read_file
    assess each draft:
    READINESS: ready | needs-revision | needs-seo-pass
    PRIORITY: which should publish first based on topic freshness and keyword opportunity
    write a prioritised publish queue to ~/content/queue/publish-queue-${DATE}.txt"

    cat ~/content/queue/publish-queue-${DATE}.txt

    # Move approved drafts to queue
    apex "read ~/content/queue/publish-queue-${DATE}.txt using read_file
    for drafts marked READY: copy their filenames to ~/content/queue/ready-${DATE}.txt"
}

# ── WEEKLY PERFORMANCE REPORT ─────────────────────────────
weekly() {
    apex "read all reports in ~/content/reports from this week using read_file
    read ~/content/published/ using read_file
    write a weekly content performance report for ${BRAND} week ${WEEK}:
    VOLUME: drafts created published in queue
    TOPIC COVERAGE: which clusters from ${TOPICS} were covered
    SEO SCORES: average score and range across published pieces
    GAPS: topic clusters with no coverage this week
    NEXT WEEK PRIORITIES: top 3 recommendations
    write to ~/content/reports/weekly-${WEEK}-${DATE}.txt"

    cat ~/content/reports/weekly-${WEEK}-${DATE}.txt
}

# ── ARCHIVE ───────────────────────────────────────────────
archive() {
    YESTERDAY=$(date_yesterday)
    ARCHIVE=~/content/archives/${YESTERDAY}.tar.gz
    if [[ ! -f "$ARCHIVE" ]]; then
        find ~/content/{signals,reports} -maxdepth 1 -name "*${YESTERDAY}*" -print0 | \
            tar czf "$ARCHIVE" --null -T - 2>/dev/null || true
    fi
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)      morning ;;
    weekly-plan)  weekly_plan ;;
    draft)        draft "$@" ;;
    seo-score)    seo_score "$@" ;;
    publish-queue) publish_queue ;;
    weekly)       weekly ;;
    archive)      archive ;;
    *) echo "Commands: morning | weekly-plan | draft [brief_file] | seo-score <draft> | publish-queue | weekly" ;;
esac
