#!/usr/bin/env bash
# ============================================================
# due-diligence-personal.sh — Professional background brief
# Requires: apex
# Usage:    ./due-diligence-personal.sh "Full Name" [context]
# context:  potential_hire | investor | partner | vendor | board_candidate
# Example:  ./due-diligence-personal.sh "Jane Smith" investor
# Note:     Uses only publicly available information.
# ============================================================
set -euo pipefail

NAME="${1:-}"
CONTEXT="${2:-partner}"
DATE=$(date +%Y-%m-%d_%H%M%S)
SLUG=$(echo "$NAME" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
mkdir -p ~/diligence/{raw,analysis,final,logs}

if [[ -z "$NAME" ]]; then
    echo "Usage: $0 \"Full Name\" [potential_hire|investor|partner|vendor|board_candidate]"
    exit 1
fi

QUERY=$(echo "$NAME" | tr ' ' '+')

echo "▶ Subject  : $NAME"
echo "▶ Context  : $CONTEXT"
echo ""

# ── PHASE 1: PUBLIC SIGNAL COLLECTION (parallel) ──────────
echo "── Collecting public signals in parallel..."

apex "fetch https://hn.algolia.com/api/v1/search?query=${QUERY}&tags=comment \
using http_get \
extract any comments or posts attributed to or mentioning ${NAME} \
write to ~/diligence/raw/hn-${SLUG}-${DATE}.txt" &

apex "fetch https://www.google.com/search?q=${QUERY}+linkedin+profile \
using http_get \
extract any professional background information visible in search snippets \
write to ~/diligence/raw/linkedin-${SLUG}-${DATE}.txt" &

apex "fetch https://www.google.com/search?q=${QUERY}+site:github.com \
using http_get \
extract any GitHub activity, projects, or contributions visible in snippets \
write to ~/diligence/raw/github-${SLUG}-${DATE}.txt" &

apex "fetch https://www.google.com/search?q=${QUERY}+news \
using http_get \
extract any news mentions, press coverage, or notable events \
note publication names and approximate dates \
write to ~/diligence/raw/news-${SLUG}-${DATE}.txt" &

apex "fetch https://www.google.com/search?q=${QUERY}+company+founder+CEO+executive \
using http_get \
extract any company affiliations, executive roles, or business ventures \
write to ~/diligence/raw/professional-${SLUG}-${DATE}.txt" &

wait

# ── PHASE 2: SIGNAL ANALYSIS (parallel) ───────────────────
echo "── Analysing signals..."

apex "read ~/diligence/raw/professional-${SLUG}-${DATE}.txt \
~/diligence/raw/linkedin-${SLUG}-${DATE}.txt using read_file \
construct a professional timeline for ${NAME}: \
companies, roles, tenure, progression pattern, \
flag any gaps, overlaps, or inconsistencies in the narrative \
write to ~/diligence/analysis/career-${SLUG}-${DATE}.txt" &

apex "read ~/diligence/raw/hn-${SLUG}-${DATE}.txt \
~/diligence/raw/github-${SLUG}-${DATE}.txt using read_file \
assess technical credibility signals for ${NAME}: \
nature of public contributions, quality of discourse, \
communities engaged with, any notable projects or open source work \
write to ~/diligence/analysis/technical-${SLUG}-${DATE}.txt" &

apex "read ~/diligence/raw/news-${SLUG}-${DATE}.txt using read_file \
identify any reputational signals for ${NAME}: \
positive coverage, controversies, legal mentions, regulatory issues, \
pattern of media narrative over time \
write to ~/diligence/analysis/reputation-${SLUG}-${DATE}.txt" &

wait

# ── PHASE 3: RISK ASSESSMENT ──────────────────────────────
apex "read all analysis files from ~/diligence/analysis/ that contain ${SLUG}-${DATE} \
using read_file \
produce a risk assessment for ${NAME} in the context of: ${CONTEXT} \
identify: green flags (strong signals), yellow flags (needs verification), \
red flags (genuine concerns), unknowns (gaps in public record) \
write to ~/diligence/analysis/risk-${SLUG}-${DATE}.txt"

# ── PHASE 4: FINAL BRIEF ──────────────────────────────────
apex "read all files in ~/diligence/analysis/ that contain ${SLUG}-${DATE} \
using read_file \
write a structured professional due diligence brief on ${NAME} \
for the purpose of: ${CONTEXT} \
sections: IDENTITY CONFIRMATION | PROFESSIONAL HISTORY | \
TECHNICAL CREDIBILITY | REPUTATIONAL SIGNALS | RISK ASSESSMENT | \
VERIFICATION GAPS | OVERALL VERDICT \
overall verdict must be: PROCEED | PROCEED WITH CAUTION | DO NOT PROCEED \
with one-paragraph rationale \
note: all findings are based on publicly available information only \
write to ~/diligence/final/brief-${SLUG}-${DATE}.txt"

echo ""
cat ~/diligence/final/brief-${SLUG}-${DATE}.txt
echo ""
echo "  Raw signals : ~/diligence/raw/"
echo "  Analysis    : ~/diligence/analysis/"
echo "  Final brief : ~/diligence/final/brief-${SLUG}-${DATE}.txt"
