#!/usr/bin/env bash
# ============================================================
# venture-bootstrap.sh — Opportunity → deployable business plan
# Requires: apex, curl
# Usage:    ./venture-bootstrap.sh "RAG-as-a-service for law firms"
# Output:   ~/ventures/<slug>/
# ============================================================
set -euo pipefail

OPPORTUNITY="${1:-$(cat ~/business/thesis/brief-$(date +%Y-%m-%d).txt | head -1)}"
DATE=$(date +%Y-%m-%d)
SLUG=$(echo "$OPPORTUNITY" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-' | cut -c1-40)
DIR=~/ventures/${SLUG}
mkdir -p "${DIR}"/{research,model,outreach,deployment,logs}

echo "Bootstrapping: ${OPPORTUNITY}"
echo "Output: ${DIR}"

# ── PHASE 1: MARKET RESEARCH (parallel) ───────────────────
apex "research the market for: ${OPPORTUNITY} \
identify: market size, key competitors, pricing benchmarks, \
customer pain points, and why existing solutions fail \
write to ${DIR}/research/market.txt" &

apex "research: what stack would be needed to build ${OPPORTUNITY} \
cross-reference against available stack: Python, Gemini API, apex-cli, rag-pipeline, \
api-integration-framework, Flask, Docker, GCP Cloud Run \
identify build vs buy decisions and estimated time to MVP \
write to ${DIR}/research/stack.txt" &

apex "research: what are the legal, compliance, or regulatory considerations \
for operating a business in this space: ${OPPORTUNITY} \
write to ${DIR}/research/legal.txt" &

wait

# ── PHASE 2: BUSINESS MODEL ───────────────────────────────
apex "read ${DIR}/research/market.txt \
${DIR}/research/stack.txt \
and design an optimal business model for: ${OPPORTUNITY} \
include: PRICING MODEL | REVENUE STREAMS | UNIT ECONOMICS | \
CUSTOMER ACQUISITION STRATEGY | FIRST 10 CUSTOMERS APPROACH | \
AUTOMATION RATIO (what % can APEX handle) | HUMAN TOUCHPOINTS \
write to ${DIR}/model/business-model.txt"

# ── PHASE 3: MVP SPEC ─────────────────────────────────────
apex "read ${DIR}/research/stack.txt \
${DIR}/model/business-model.txt \
and write a minimal MVP specification: \
CORE FEATURE SET (must-haves only) | WHAT TO CUT | \
APEX AUTOMATION POINTS | DEPLOYMENT TARGET | \
WEEK 1 BUILD PLAN | DEFINITION OF DONE \
write to ${DIR}/model/mvp-spec.txt"

# ── PHASE 4: OUTREACH ASSETS ──────────────────────────────
apex "read ${DIR}/model/business-model.txt \
${DIR}/research/market.txt \
and write: \
(1) cold outreach email for first 10 customers (under 100 words, no fluff) \
(2) one-paragraph product description for GitHub/landing page \
(3) 3 subject line variants for cold email \
write to ${DIR}/outreach/assets.txt"

# ── PHASE 5: DEPLOYMENT CHECKLIST ────────────────────────
apex "read ${DIR}/model/mvp-spec.txt \
and generate a deployment checklist: \
infrastructure setup, env vars, CI/CD, monitoring, \
first customer onboarding steps \
write to ${DIR}/deployment/checklist.txt"

# ── PHASE 6: EXECUTIVE SUMMARY ────────────────────────────
apex "read all files in ${DIR}/research \
${DIR}/model/business-model.txt \
${DIR}/model/mvp-spec.txt \
and write a one-page executive summary: \
OPPORTUNITY | WHY NOW | UNFAIR ADVANTAGE (deterministic AI stack) | \
BUSINESS MODEL | MVP | PATH TO \$10K MRR | RISKS \
write to ${DIR}/SUMMARY.txt"

cat "${DIR}/SUMMARY.txt"

# ── PHASE 7: RESUME + LOG ─────────────────────────────────
apex "read ${DIR}/SUMMARY.txt \
and append a one-line venture entry to ~/axiom-llc/ventures-log.md: \
date, opportunity name, stage (bootstrapped), key metric target"

echo "Bootstrap complete: ${DIR}"
echo "Next: review ${DIR}/SUMMARY.txt and ${DIR}/model/mvp-spec.txt"
