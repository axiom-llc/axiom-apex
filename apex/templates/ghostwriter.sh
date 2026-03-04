#!/usr/bin/env bash
# ============================================================
# ghostwriter.sh — Voice-cloning content generator
# Requires: apex
# Config:   echo "/path/to/writing/samples/" > ~/.config/apex/voice_samples
#           echo "linkedin" > ~/.config/apex/ghostwriter_format
# Usage:    ./ghostwriter.sh "topic or brief" [format] [word_count]
# Formats:  linkedin | twitter_thread | blog | email | essay | newsletter
# Example:  ./ghostwriter.sh "why async communication beats meetings" linkedin 300
# ============================================================
set -euo pipefail

BRIEF="${1:-}"
FORMAT="${2:-$(cat ~/.config/apex/ghostwriter_format 2>/dev/null || echo "linkedin")}"
WORDS="${3:-300}"
SAMPLES=$(cat ~/.config/apex/voice_samples 2>/dev/null || echo "")
DATE=$(date +%Y-%m-%d_%H%M%S)
mkdir -p ~/ghostwriter/{voice,drafts,final,logs}

if [[ -z "$BRIEF" ]]; then
    echo "Usage: $0 \"topic or brief\" [linkedin|twitter_thread|blog|email|essay|newsletter] [word_count]"
    exit 1
fi

VOICE_PROFILE=~/ghostwriter/voice/profile.txt
STYLE_RULES=~/ghostwriter/voice/style_rules.txt

# ── PHASE 1: VOICE EXTRACTION (once, cached) ──────────────
if [[ ! -f "$VOICE_PROFILE" ]]; then
    echo "── Building voice profile from samples..."

    if [[ -n "$SAMPLES" && -d "$SAMPLES" ]]; then
        apex "read all text files in ${SAMPLES} using read_file \
        and construct a detailed voice profile covering: \
        sentence length distribution, vocabulary level, punctuation habits, \
        rhetorical devices used, opening and closing patterns, \
        how the author handles data vs anecdote, \
        tonal range from casual to formal, common transitional phrases, \
        what topics they avoid, what they obsess over, \
        and 10 signature phrases or constructions verbatim from the samples. \
        write to ${VOICE_PROFILE} using write_file"

        apex "read ${VOICE_PROFILE} using read_file \
        and distil into 15 concrete style rules a ghostwriter must follow, \
        each rule one sentence, specific and actionable, no vague guidance. \
        write to ${STYLE_RULES} using write_file"
    else
        echo "⚠ No voice samples configured. Writing in neutral professional voice."
        echo "No voice samples provided. Use neutral, clear, professional tone." > "$VOICE_PROFILE"
        echo "1. Write clearly. 2. Be direct. 3. No filler." > "$STYLE_RULES"
    fi
fi

# ── PHASE 2: CONTENT RESEARCH (parallel) ──────────────────
apex "research the topic: ${BRIEF} \
fetch relevant data, recent developments, counterarguments, and concrete examples \
from https://hn.algolia.com/api/v1/search?query=$(echo "$BRIEF" | tr ' ' '+')&tags=story \
write findings to ~/ghostwriter/drafts/research-${DATE}.txt" &

apex "read ${VOICE_PROFILE} using read_file \
and identify 3 angles the author would likely take on this topic: ${BRIEF} \
based on their demonstrated worldview and obsessions. \
write angles to ~/ghostwriter/drafts/angles-${DATE}.txt" &

wait

# ── PHASE 3: DRAFT GENERATION (parallel, 3 variants) ──────
echo "── Generating 3 draft variants..."

apex "read ${STYLE_RULES} ${VOICE_PROFILE} \
~/ghostwriter/drafts/research-${DATE}.txt \
~/ghostwriter/drafts/angles-${DATE}.txt using read_file \
write a ${FORMAT} post on: ${BRIEF} \
exactly ${WORDS} words, variant A: opens with a bold counterintuitive claim \
follow every style rule precisely \
write to ~/ghostwriter/drafts/draft-A-${DATE}.txt using write_file" &

apex "read ${STYLE_RULES} ${VOICE_PROFILE} \
~/ghostwriter/drafts/research-${DATE}.txt \
~/ghostwriter/drafts/angles-${DATE}.txt using read_file \
write a ${FORMAT} post on: ${BRIEF} \
exactly ${WORDS} words, variant B: opens with a specific concrete story or scenario \
follow every style rule precisely \
write to ~/ghostwriter/drafts/draft-B-${DATE}.txt using write_file" &

apex "read ${STYLE_RULES} ${VOICE_PROFILE} \
~/ghostwriter/drafts/research-${DATE}.txt \
~/ghostwriter/drafts/angles-${DATE}.txt using read_file \
write a ${FORMAT} post on: ${BRIEF} \
exactly ${WORDS} words, variant C: opens with a data point or surprising statistic \
follow every style rule precisely \
write to ~/ghostwriter/drafts/draft-C-${DATE}.txt using write_file" &

wait

# ── PHASE 4: VOICE SCORING + SELECTION ────────────────────
apex "read ${STYLE_RULES} ${VOICE_PROFILE} using read_file \
read the three drafts: \
~/ghostwriter/drafts/draft-A-${DATE}.txt \
~/ghostwriter/drafts/draft-B-${DATE}.txt \
~/ghostwriter/drafts/draft-C-${DATE}.txt using read_file \
score each draft 1-10 on: voice fidelity, engagement hook, argument strength, format fit \
select the winner, explain why in 2 sentences \
write the winning draft verbatim to ~/ghostwriter/final/post-${DATE}.txt using write_file \
write the score breakdown to ~/ghostwriter/final/scores-${DATE}.txt using write_file"

# ── PHASE 5: FINAL POLISH ─────────────────────────────────
apex "read ~/ghostwriter/final/post-${DATE}.txt ${STYLE_RULES} using read_file \
do a final pass: tighten every sentence, remove any phrase that sounds AI-generated, \
ensure the opening line earns attention in under 8 words, \
ensure the closing line has weight. \
write final polished version to ~/ghostwriter/final/FINAL-${DATE}.txt using write_file"

echo ""
echo "══════════════════════════════════════════"
cat ~/ghostwriter/final/FINAL-${DATE}.txt
echo ""
echo "══════════════════════════════════════════"
echo "  Draft dir : ~/ghostwriter/drafts/"
echo "  Final     : ~/ghostwriter/final/FINAL-${DATE}.txt"
