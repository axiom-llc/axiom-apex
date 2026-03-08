#!/usr/bin/env bash
# ============================================================
# opportunity-scanner.sh — Recursive business opportunity research
# Requires: apex, curl
# Config:   echo "AI,automation,SaaS,developer-tools" > ~/.config/apex/domains
#           echo "solo,smb,enterprise" > ~/.config/apex/target-markets
# Cron:     0 7 * * 1 ~/path/to/opportunity-scanner.sh >> ~/business/logs/scanner.log 2>&1
# ============================================================
set -euo pipefail

DATE=$(date +%Y-%m-%d)
DOMAINS=$(cat ~/.config/apex/domains 2>/dev/null || echo "AI,automation,SaaS,developer-tools")
MARKETS=$(cat ~/.config/apex/target-markets 2>/dev/null || echo "solo,smb,enterprise")
mkdir -p ~/business/{signals,opportunities,thesis,logs,archives}

# ── PHASE 1: MARKET SIGNAL INGESTION (parallel) ───────────
apex "fetch https://news.ycombinator.com/rss using http_get \
and extract all stories about new products, market gaps, or underserved problems \
in domains: ${DOMAINS} \
and write to ~/business/signals/hn-${DATE}.txt" &

apex "fetch https://www.producthunt.com/feed using http_get \
and extract top launched products today with upvotes and descriptions \
and write to ~/business/signals/ph-${DATE}.txt" &

apex "fetch https://feeds.a.dj.com/rss/RSSMarketsMain.xml using http_get \
and extract headlines signaling new business regulation, market openings, or tech shifts \
and write to ~/business/signals/wsj-${DATE}.txt" &

apex "fetch https://api.hnpwa.com/v0/jobs/1.json using http_get \
and extract all job postings — identify repeated role patterns that signal emerging demand \
and write to ~/business/signals/jobs-${DATE}.txt" &

wait

# ── PHASE 2: STACK ALIGNMENT ANALYSIS ────────────────────
apex "read ~/business/signals/hn-${DATE}.txt \
~/business/signals/ph-${DATE}.txt \
~/business/signals/jobs-${DATE}.txt \
and cross-reference against stack: Python, Gemini API, RAG, deterministic agents, \
Flask, Docker, GCP Cloud Run, OpenSCAD \
and identify opportunities where current Axiom LLC stack maps directly to unmet demand \
and write to ~/business/signals/stack-aligned-${DATE}.txt" &

# ── PHASE 3: COMPETITOR GAP ANALYSIS ─────────────────────
apex "read ~/business/signals/ph-${DATE}.txt \
~/business/signals/hn-${DATE}.txt \
and identify products with high demand but weak determinism, poor reliability, \
or no grounding discipline — gaps where a deterministic AI approach wins \
and write to ~/business/signals/gaps-${DATE}.txt" &

wait

# ── PHASE 4: OPPORTUNITY SCORING ─────────────────────────
apex "read ~/business/signals/stack-aligned-${DATE}.txt \
~/business/signals/gaps-${DATE}.txt \
~/business/signals/wsj-${DATE}.txt \
and generate 5 ranked business opportunities. For each include: \
OPPORTUNITY | TARGET MARKET | BARRIER TO ENTRY (1-10) | \
AUTOMATION POTENTIAL (1-10) | REVENUE CEILING | TIME TO FIRST REVENUE | \
STACK FIT | WHY NOW \
write to ~/business/opportunities/scored-${DATE}.txt"

# ── PHASE 5: THESIS ───────────────────────────────────────
apex "read ~/business/opportunities/scored-${DATE}.txt \
and write a strategic opportunity brief with: \
TOP PICK | RATIONALE | FIRST 3 ACTIONS | RISK FLAGS | \
TECH ACCELERATION NOTE (how singularity trajectory affects this opportunity) \
to ~/business/thesis/thesis-${DATE}.txt"

# ── PHASE 6: EXECUTIVE BRIEF ──────────────────────────────
apex "read ~/business/thesis/thesis-${DATE}.txt \
and distill to 5 bullets, each under 20 words, action-oriented \
write to ~/business/thesis/brief-${DATE}.txt"

cat ~/business/thesis/brief-${DATE}.txt

# ── PHASE 7: RESUME SIGNAL CAPTURE ───────────────────────
apex "read ~/business/opportunities/scored-${DATE}.txt \
and extract any opportunities pursued or validated this week \
and append a one-line entry to ~/axiom-llc/business-log.md with date and opportunity name"

# ── PHASE 8: ARCHIVE ──────────────────────────────────────
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
ARCHIVE=~/business/archives/${YESTERDAY}.tar.gz
if [[ ! -f "$ARCHIVE" ]]; then
    find ~/business/{signals,opportunities,thesis} \
        -maxdepth 1 -name "*${YESTERDAY}*" -print0 | \
        tar czf "$ARCHIVE" --null -T - 2>/dev/null || true
fi
