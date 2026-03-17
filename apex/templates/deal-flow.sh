#!/usr/bin/env bash
# ============================================================
# deal-flow.sh — VC/angel inbound deal triage and scoring
# Requires: apex
# Config:   ~/.config/apex/fund_name    — fund or investor name
#           ~/.config/apex/fund_thesis  — investment thesis (plain text)
#           ~/.config/apex/fund_stage   — stage focus (e.g. pre-seed, seed)
#           ~/.config/apex/fund_sectors — focus sectors (comma-separated)
# Cron:     0 7 * * 1-5  ./deal-flow.sh morning
# Usage:    ./deal-flow.sh triage pitch-deck-notes.txt
#           ./deal-flow.sh deep-dive "Acme Corp"
# ============================================================
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

FUND="${FUND:-$(cat ~/.config/apex/fund_name 2>/dev/null || echo "Your Fund")}"
THESIS_FILE="${THESIS_FILE:-${HOME}/.config/apex/fund_thesis}"
STAGE=$(cat ~/.config/apex/fund_stage   2>/dev/null || echo "pre-seed, seed")
SECTORS=$(cat ~/.config/apex/fund_sectors 2>/dev/null || echo "AI, software, developer tools")
DATE=$(date +%Y-%m-%d)
WEEK=$(date +%V)

mkdir -p ~/dealflow/{inbox,triage,research,memos,passed,portfolio,reports,logs,archives}

CMD=${1:-morning}

# ── MORNING DEAL BRIEF ────────────────────────────────────
morning() {
    log ~/dealflow/logs/dealflow.log "Morning deal brief..."

    # Parallel: inbox triage + market signals + portfolio check-ins
    apex "read all pitch files in ~/dealflow/inbox/ that do not have a corresponding \
    file in ~/dealflow/triage/ using read_file
    count untriaged pitches
    flag any marked URGENT or from warm intros
    write inbox status to ~/dealflow/reports/inbox-status-${DATE}.txt" &

    apex "fetch https://news.ycombinator.com/rss using http_get
    fetch https://api.hnpwa.com/v0/news/1.json using http_get
    extract signals relevant to sectors: ${SECTORS}
    identify: new market entrants, regulatory changes, technology shifts, \
    companies raising that you haven't seen, failed competitors
    write to ~/dealflow/reports/market-signals-${DATE}.txt" &

    apex "read all files in ~/dealflow/portfolio/ using read_file
    identify portfolio companies with no update in 30+ days
    flag any requiring check-in or follow-up
    write to ~/dealflow/reports/portfolio-${DATE}.txt" &

    wait

    apex "read ~/dealflow/reports/inbox-status-${DATE}.txt
    ~/dealflow/reports/market-signals-${DATE}.txt
    ~/dealflow/reports/portfolio-${DATE}.txt using read_file
    write morning deal brief for ${FUND} on ${DATE}:
    INBOX: untriaged pitches requiring action today
    MARKET SIGNALS: themes and movements relevant to ${SECTORS}
    PORTFOLIO PULSE: companies needing attention
    PRIORITY ACTIONS TODAY: ranked list
    write to ~/dealflow/reports/morning-${DATE}.txt"

    cat ~/dealflow/reports/morning-${DATE}.txt
    log ~/dealflow/logs/dealflow.log "Morning brief complete."
}

# ── TRIAGE A PITCH ────────────────────────────────────────
triage() {
    PITCH_FILE="${2:-}"
    require_file "$PITCH_FILE" "Usage: $0 triage <pitch_file>"

    DEAL_ID="DEAL-$(date +%s)"
    local thesis_context=""
    [[ -f "$THESIS_FILE" ]] && thesis_context=$(cat "$THESIS_FILE")

    # Phase 1: thesis fit (fast, single call)
    apex "read the pitch at ${PITCH_FILE} using read_file

    Investment context for ${FUND}:
    Stage focus: ${STAGE}
    Sectors: ${SECTORS}
    Thesis: ${thesis_context:-not specified}

    Perform rapid deal triage. Score each dimension 1-10:
    THESIS_FIT:       does this fit our stage, sector, and investment thesis?
    MARKET_SIZE:      TAM signal from the pitch — is it credible and large enough?
    FOUNDER_SIGNAL:   what does the team's background suggest about execution ability?
    TRACTION:         any evidence of product-market fit, revenue, or user growth?
    DIFFERENTIATION:  is there a genuine moat or is this easily replicated?
    TIMING:           why now — what has changed to make this opportunity exist?

    OVERALL SCORE: /60
    DECISION: PASS | SOFT PASS | INTERESTED | PRIORITY
    ONE-LINE RATIONALE: why this decision in ≤20 words
    RED FLAGS: list any deal-killers
    NEXT STEP: if not PASS — specific single action (call, data request, reference check)

    Write triage report to ~/dealflow/triage/${DEAL_ID}-triage-${DATE}.txt"

    apex "append ${DEAL_ID} $(date +%H:%M) $(basename ${PITCH_FILE}) pending \
    to ~/dealflow/triage/deal-register.txt"

    cat ~/dealflow/triage/${DEAL_ID}-triage-${DATE}.txt

    # Auto-route based on decision
    DECISION=$(grep -oE "DECISION: (PASS|SOFT PASS|INTERESTED|PRIORITY)" \
        ~/dealflow/triage/${DEAL_ID}-triage-${DATE}.txt 2>/dev/null | \
        awk '{print $2, $3}' | head -1 || echo "PENDING")

    case "$DECISION" in
        PASS)
            _draft_pass_email "$DEAL_ID" "$PITCH_FILE"
            echo "→ Routed: PASS (pass email drafted)"
            ;;
        "SOFT PASS")
            echo "→ Routed: SOFT PASS (add to watchlist)"
            apex "append ${DEAL_ID} $(date +%H:%M) SOFT_PASS $(basename ${PITCH_FILE}) \
            to ~/dealflow/passed/watchlist.txt"
            ;;
        INTERESTED|PRIORITY)
            echo "→ Routed: ${DECISION} — recommend deep-dive"
            echo "   Run: $0 deep-dive \"$(basename ${PITCH_FILE} .txt)\""
            ;;
    esac

    log ~/dealflow/logs/dealflow.log "Triage complete: ${DEAL_ID} → ${DECISION}"
    echo "Deal ID: ${DEAL_ID}"
}

# ── DEEP DIVE ─────────────────────────────────────────────
deep_dive() {
    COMPANY="${2:-}"
    [[ -z "$COMPANY" ]] && echo "Usage: $0 deep-dive \"Company Name\"" && exit 1

    DEAL_ID="DD-$(date +%s)"
    local thesis_context=""
    [[ -f "$THESIS_FILE" ]] && thesis_context=$(cat "$THESIS_FILE")

    echo "▶ Deep dive: ${COMPANY}"
    echo "▶ Output: ~/dealflow/memos/${DEAL_ID}-${DATE}.md"

    # Phase 1: parallel research
    PIDS=()
    local query
    query=$(echo "$COMPANY" | tr ' ' '+')

    apex "fetch https://hn.algolia.com/api/v1/search?query=${query}&tags=story \
    using http_get
    extract all HN stories mentioning ${COMPANY} — sentiment, technical credibility, \
    team reputation in developer community
    write to ~/dealflow/research/${DEAL_ID}-hn.txt" &
    PIDS+=($!)

    apex "fetch https://hn.algolia.com/api/v1/search?query=${query}+funding+seed+series \
    using http_get
    extract any funding announcements or investor mentions
    write to ~/dealflow/research/${DEAL_ID}-funding.txt" &
    PIDS+=($!)

    apex "research market context for ${COMPANY} in sectors: ${SECTORS}
    identify: top 3 direct competitors and their last funding rounds,
    any recent M&A in this space, publicly known customer logos if any
    write to ~/dealflow/research/${DEAL_ID}-market.txt" &
    PIDS+=($!)

    wait_pids "${PIDS[@]}" || true

    # Phase 2: investment memo
    apex "read all research files ~/dealflow/research/${DEAL_ID}-*.txt using read_file
    read any triage file for ${COMPANY} in ~/dealflow/triage/ using read_file

    Write an investment memo for ${FUND} on ${COMPANY}:

    # Investment Memo: ${COMPANY}
    **Date:** ${DATE} | **Stage:** ${STAGE} | **Fund:** ${FUND}

    ## Thesis Alignment
    (Does this fit our thesis? ${thesis_context:-Reference fund_thesis file.} Map explicitly.)

    ## Company Overview
    (What they do, business model, how they make money)

    ## Market
    (TAM/SAM, competitive landscape, timing — why now)

    ## Team Assessment
    (Founder backgrounds, relevant experience, execution signals from public data)

    ## Traction
    (Revenue, users, growth rate — note if self-reported and unverified)

    ## Differentiation
    (Genuine moat vs. feature advantage vs. easily replicated)

    ## Key Risks
    (Ranked: most likely to kill the deal first)

    ## What We Would Need to See
    (Specific diligence items before committing: reference calls, financials, tech review)

    ## Preliminary Recommendation
    PASS | INVEST | INVEST WITH CONDITIONS — with clear rationale

    ---
    *Preliminary memo. Requires founder call and financial verification before IC.*

    Write to ~/dealflow/memos/${DEAL_ID}-${DATE}.md"

    cat ~/dealflow/memos/${DEAL_ID}-${DATE}.md
    log ~/dealflow/logs/dealflow.log "Deep dive complete: ${COMPANY} → ${DEAL_ID}"
}

# ── DRAFT PASS EMAIL ─────────────────────────────────────
_draft_pass_email() {
    local deal_id="$1"
    local pitch_file="$2"

    apex "read the triage at ~/dealflow/triage/${deal_id}-triage-${DATE}.txt \
    and the pitch at ${pitch_file} using read_file
    draft a respectful, specific pass email from ${FUND}:
    - Reference one specific thing from the pitch (shows we read it)
    - Give the real reason we are passing — no generic 'not a fit'
    - Leave the door open if circumstances change
    - Under 100 words
    - No corporate boilerplate
    write to ~/dealflow/passed/${deal_id}-pass-email-${DATE}.txt"

    echo "   Pass email: ~/dealflow/passed/${deal_id}-pass-email-${DATE}.txt"
}

# ── BATCH TRIAGE INBOX ────────────────────────────────────
triage_inbox() {
    local pitches
    pitches=$(find ~/dealflow/inbox/ -name "*.txt" -o -name "*.md" 2>/dev/null | head -20)
    [[ -z "$pitches" ]] && echo "Inbox empty." && exit 0

    PIDS=()
    while IFS= read -r pitch_file; do
        [[ -z "$pitch_file" ]] && continue
        ( triage "$CMD" "$pitch_file" ) &
        PIDS+=($!)
    done <<< "$pitches"

    wait_pids "${PIDS[@]}" || true

    apex "read all triage reports created today in ~/dealflow/triage using read_file
    write batch triage summary: total triaged by decision category, \
    deals recommended for deep dive, total pass rate
    write to ~/dealflow/reports/triage-batch-${DATE}.txt"

    cat ~/dealflow/reports/triage-batch-${DATE}.txt
}

# ── WEEKLY PIPELINE REVIEW ────────────────────────────────
weekly() {
    apex "read all triage reports and memos from this week in ~/dealflow using read_file
    write weekly deal flow review for ${FUND} week ${WEEK}:
    VOLUME: pitches received triaged by decision
    PIPELINE: deals in INTERESTED or PRIORITY status
    PASS RATE: overall and by sector
    MARKET THEMES: patterns across this week's deal flow
    PORTFOLIO: any companies requiring attention
    NEXT WEEK FOCUS: specific deals to advance
    write to ~/dealflow/reports/weekly-${WEEK}-${DATE}.txt"

    cat ~/dealflow/reports/weekly-${WEEK}-${DATE}.txt
}

# ── ARCHIVE ───────────────────────────────────────────────
archive() {
    local yesterday
    yesterday=$(date_yesterday)
    local archive=~/dealflow/archives/${yesterday}.tar.gz
    if [[ ! -f "$archive" ]]; then
        find ~/dealflow/{research,reports} -maxdepth 1 -name "*${yesterday}*" -print0 | \
            tar czf "$archive" --null -T - 2>/dev/null || true
    fi
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)        morning ;;
    triage)         triage "$@" ;;
    triage-inbox)   triage_inbox ;;
    deep-dive)      deep_dive "$@" ;;
    weekly)         weekly ;;
    archive)        archive ;;
    *)  echo "Commands: morning | triage <pitch_file> | triage-inbox | deep-dive \"Company\" | weekly" ;;
esac
