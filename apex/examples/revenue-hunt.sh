#!/usr/bin/env bash
# revenue-hunt.sh — Autonomous revenue opportunity identification and execution swarm
# Feed it what you have: skills, a product, a market, a company description.
# The swarm finds the highest-ROI opportunity and produces ready-to-execute artifacts.
#
# Usage: ./revenue-hunt.sh "input" [budget_constraint] [time_horizon_days]
# input: your skills, product, company description, or market position
# budget_constraint: bootstrap | low | funded (default: bootstrap)
# time_horizon_days: how soon you need revenue (default: 90)
#
# Example:
#   ./revenue-hunt.sh "Python automation and AI integration, 1 developer, B2B focus" bootstrap 60
#   ./revenue-hunt.sh "$(cat company-profile.md)" low 90
#   ./revenue-hunt.sh "no-code SaaS tools for small law firms" funded 120

set -euo pipefail

INPUT="${1:-}"
BUDGET="${2:-bootstrap}"
HORIZON="${3:-90}"
APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

if [[ -z "$INPUT" ]]; then
    echo "Usage: $0 \"skills/product/market description\" [bootstrap|low|funded] [days]"
    exit 1
fi

OUTDIR="$HOME/swarm/revenue-hunt/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"
cd "$APEX_ROOT"

# Output files
OPPORTUNITIES="$OUTDIR/opportunities.md"
FINANCIAL_MODELS="$OUTDIR/financial_models.md"
COMPETITIVE="$OUTDIR/competitive.md"
WINNER="$OUTDIR/winner.md"
GTM="$OUTDIR/gtm_plan.md"
OUTREACH="$OUTDIR/outreach.md"
LANDING="$OUTDIR/landing_page.md"
PRICING="$OUTDIR/pricing.md"
OBJECTIONS="$OUTDIR/objections.md"
FINAL="$OUTDIR/EXECUTION_PLAN.md"

echo "▶ Input    : ${INPUT:0:80}..."
echo "▶ Budget   : $BUDGET"
echo "▶ Horizon  : ${HORIZON} days"
echo "▶ Output   : $OUTDIR"
echo ""

# ── Phase 1: Opportunity generation ───────────────────────────────────────────
echo "══════════════════════════════════════════"
echo "  PHASE 1 — OPPORTUNITY IDENTIFICATION"
echo "══════════════════════════════════════════"
echo ""
echo "── [Agent 1] Scanning for revenue opportunities..."

apex "You are a revenue strategist with deep knowledge of B2B markets, SaaS, services, and digital products.

Context:
- What we have: ${INPUT}
- Budget constraint: ${BUDGET} (bootstrap = near-zero capex; low = <\$5k; funded = <\$50k)
- Time to revenue target: ${HORIZON} days

Generate exactly 5 specific, distinct revenue opportunities. For each:

**Opportunity N: [Name]**
- Model: [productized service | SaaS | marketplace | consulting | info product | API | other]
- Target customer: specific company type, size, role of buyer
- Problem solved: one sentence, concrete
- Why now: why is this underserved or newly possible
- Unfair advantage: why our specific input gives an edge here
- Time to first dollar: realistic estimate in days
- Revenue ceiling: realistic 12-month ceiling for a solo operator
- Capital required: honest estimate given budget constraint

Rank them 1–5 by expected ROI within the time horizon, not by how exciting they sound.
Be specific. No generic 'build an AI chatbot' entries.
Cite real companies, real pricing benchmarks, real buyer personas where possible.

Write to ${OPPORTUNITIES} using write_file"

[[ ! -f "$OPPORTUNITIES" ]] && echo "✗ Phase 1 failed" && exit 1
echo "   ✓ 5 opportunities identified"

# ── Phase 2: Financial modelling + competitive analysis in parallel ────────────
echo ""
echo "══════════════════════════════════════════"
echo "  PHASE 2 — FINANCIAL + COMPETITIVE"
echo "══════════════════════════════════════════"
echo ""
echo "── [Agents 2 & 3] Financial modelling and competitive analysis in parallel..."

(
    apex "You are a financial modeller. Build honest financial models for 5 business opportunities.

Read the opportunities from ${OPPORTUNITIES} using read_file.

For each opportunity, produce a model with:

**[Opportunity Name]**
- Pricing: recommended price point and rationale (anchor to market comps)
- Sales cycle: days from first contact to closed deal, realistic
- Units to ramen profitability: how many customers/sales to cover \$3k/month
- Units to \$10k MRR: target milestone
- Primary cost: what actually costs money here (time, infra, ads, etc.)
- CAC estimate: realistic customer acquisition cost for ${BUDGET} budget
- LTV estimate: realistic lifetime value
- Payback period: CAC / monthly margin
- Key assumption: the single assumption this model breaks on if wrong
- Verdict: STRONG / MARGINAL / RISKY with one-line reason

Use real SaaS/services benchmarks. Be pessimistic on conversion rates.
No hockey sticks. Model what a competent solo operator actually achieves.

Write to ${FINANCIAL_MODELS} using write_file"
) &
PID_FIN=$!

(
    apex "You are a competitive intelligence analyst.

Read the opportunities from ${OPPORTUNITIES} using read_file.

For each opportunity, produce a competitive brief:

**[Opportunity Name]**
- Direct competitors: 2–3 named companies already doing this
- Their pricing: what they charge
- Their weakness: the gap they are not serving well
- Barrier to entry: what stops someone from copying this in 30 days
- Moat: what compound advantage builds over time (data, relationships, brand, etc.)
- Kill risk: which type of competitor (Google, well-funded startup, freelancer commoditisation) is most likely to kill this and when
- Verdict: DEFENSIBLE / CROWDED / RACE-TO-BOTTOM

Write to ${COMPETITIVE} using write_file"
) &
PID_COMP=$!

wait $PID_FIN  && echo "   ✓ financial models complete" || echo "   ⚠ financial models failed"
wait $PID_COMP && echo "   ✓ competitive analysis complete" || echo "   ⚠ competitive analysis failed"

# ── Phase 3: Winner selection ──────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  PHASE 3 — WINNER SELECTION"
echo "══════════════════════════════════════════"
echo ""
echo "── [Agent 4] Selecting highest-ROI opportunity..."

apex "You are a venture operator who has built and sold multiple businesses.
You must pick one opportunity to pursue and stake your reputation on it.

Read the opportunities from ${OPPORTUNITIES} using read_file.
Read the financial models from ${FINANCIAL_MODELS} using read_file.
Read the competitive analysis from ${COMPETITIVE} using read_file.

Score each opportunity across these dimensions (1–10):
- Speed to first dollar (weight: 30%)
- 12-month revenue ceiling (weight: 25%)
- Defensibility (weight: 20%)
- Capital efficiency given ${BUDGET} budget (weight: 15%)
- Execution difficulty for a small team (weight: 10%, inverse — harder = lower score)

Show your scoring table, then select the winner.

For the winner, write a clear investment thesis:
- Why this one beats the others given our specific constraints
- The single biggest risk and how to de-risk it in the first 30 days
- What success looks like at 30 / 60 / 90 days
- The exact first action to take tomorrow morning

Write to ${WINNER} using write_file"

[[ ! -f "$WINNER" ]] && echo "✗ Phase 3 failed" && exit 1
echo "   ✓ winner selected"
cat "$WINNER"

# ── Phase 4: Execution artifacts — all in parallel ────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  PHASE 4 — EXECUTION ARTIFACTS"
echo "══════════════════════════════════════════"
echo ""
echo "── [Agents 5–8] Generating execution artifacts in parallel..."

(
    apex "You are a go-to-market strategist. Build a day-by-day execution plan.

Read the winning opportunity from ${WINNER} using read_file.
Read the financial model for the winner from ${FINANCIAL_MODELS} using read_file.

Produce a ${HORIZON}-day GTM plan structured as:

**Days 1–7: Foundation**
- Daily tasks, specific and actionable

**Days 8–30: First Revenue**
- Weekly milestones
- Definition of success at day 30

**Days 31–60: Repeatability**
- What process gets systematised
- Leading indicators to track

**Days 61–${HORIZON}: Scale**
- What changes at this stage
- Definition of success at day ${HORIZON}

Each task must be specific enough to put in a calendar.
No 'research the market' — only 'email 10 [specific company type] founders via LinkedIn asking [specific question]'.

Write to ${GTM} using write_file"
) &
PID_GTM=$!

(
    apex "You are a B2B copywriter who specialises in cold outreach that gets replies.

Read the winning opportunity from ${WINNER} using read_file.

Write 3 cold outreach sequences (email or LinkedIn DM, under 100 words each):

**Version A — Problem-led**
Lead with the pain. No pitch until the reply.

**Version B — Social proof-led**
Lead with a result or case study (invent a realistic one if needed — label it [EXAMPLE]).

**Version C — Insight-led**
Lead with a non-obvious observation about their business or industry that earns attention.

For each: subject line + body. Personalisation tokens in [brackets].
End each with a single low-friction CTA. No 'hope this finds you well'.

Write to ${OUTREACH} using write_file"
) &
PID_OUTREACH=$!

(
    apex "You are a conversion copywriter. Write a landing page for the winning opportunity.

Read the winning opportunity from ${WINNER} using read_file.
Read the competitive analysis from ${COMPETITIVE} using read_file.

Write a complete landing page in Markdown:

**Headline** — outcome-focused, under 10 words
**Subheadline** — who it's for and what it does, under 20 words
**Problem section** — 3 bullet points of pain the buyer feels daily
**Solution section** — what this does, not what it is
**How it works** — 3 steps, named and described
**Results section** — 3 specific, believable outcomes with numbers (invent realistic ones, label [EXAMPLE])
**Objection crushers** — 3 common objections, answered inline
**Pricing teaser** — one line that sets expectation without full reveal
**CTA** — one button, action-oriented copy
**FAQ** — 5 questions a skeptical buyer would actually ask

Write to ${LANDING} using write_file"
) &
PID_LANDING=$!

(
    apex "You are a pricing strategist. Design the pricing architecture for the winning opportunity.

Read the winning opportunity from ${WINNER} using read_file.
Read the financial model from ${FINANCIAL_MODELS} using read_file.
Read the competitive analysis from ${COMPETITIVE} using read_file.

Design a 3-tier pricing structure:

For each tier:
- Name (not 'Basic/Pro/Enterprise' — name it after the outcome)
- Price point and billing cadence
- Exactly what is included
- Who it is for
- Psychological role (entry / core / anchor)

Then:
- **Recommended anchor**: which tier most buyers should land on and why
- **Expansion motion**: how a customer naturally moves up tiers
- **Pricing rationale**: why these numbers, benchmarked against comps
- **First 10 customers**: should you discount? How much? What in exchange?
- **Annual vs monthly**: recommended default and why

Write to ${PRICING} using write_file"
) &
PID_PRICING=$!

wait $PID_GTM     && echo "   ✓ GTM plan complete"       || echo "   ⚠ GTM plan failed"
wait $PID_OUTREACH && echo "   ✓ outreach copy complete"  || echo "   ⚠ outreach failed"
wait $PID_LANDING  && echo "   ✓ landing page complete"   || echo "   ⚠ landing page failed"
wait $PID_PRICING  && echo "   ✓ pricing architecture complete" || echo "   ⚠ pricing failed"

# ── Phase 5: Objection + risk brief ───────────────────────────────────────────
echo ""
echo "── [Agent 9] Generating objection and risk brief..."

apex "You are a sales coach and risk analyst.

Read the winning opportunity from ${WINNER} using read_file.
Read the pricing from ${PRICING} using read_file.
Read the competitive analysis from ${COMPETITIVE} using read_file.

Produce two sections:

**Sales Objections**
List the 8 most common objections a buyer will raise. For each:
- The objection, verbatim as a buyer would say it
- The response, under 40 words, that resolves it without discounting or caving

**Execution Risks**
List the 5 most likely reasons this fails in the first 90 days. For each:
- Risk, stated plainly
- Early warning signal (what you'd see before it becomes fatal)
- Mitigation (specific action, not generic advice)

Write to ${OBJECTIONS} using write_file"

echo "   ✓ objection brief complete"

# ── Phase 6: Final synthesis ───────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  PHASE 5 — FINAL SYNTHESIS"
echo "══════════════════════════════════════════"
echo ""
echo "── [Agent 10] Compiling execution package..."

apex "You are compiling the final output of a revenue hunting swarm into a single execution document.

Read and synthesise the following files using read_file:
- Winner selection: ${WINNER}
- GTM plan: ${GTM}
- Outreach copy: ${OUTREACH}
- Landing page: ${LANDING}
- Pricing: ${PRICING}
- Objections & risks: ${OBJECTIONS}

Produce a single Markdown document structured as:

# Revenue Execution Plan
**Generated:** $(date)
**Input:** ${INPUT}
**Budget:** ${BUDGET} | **Horizon:** ${HORIZON} days

## Executive Summary
3 sentences: what we're building, who we're selling to, what success looks like.

## The Opportunity
[Paste winner thesis verbatim]

## Financial Targets
Key milestones table: day 30 / 60 / 90 / 12-month targets

## ${HORIZON}-Day Execution Plan
[Full GTM plan]

## Pricing Architecture
[Full pricing]

## Go-To-Market Assets

### Cold Outreach (3 variants)
[All 3 outreach sequences]

### Landing Page Copy
[Full landing page]

## Sales Playbook
[Objections and responses]

## Risk Register
[Risks, signals, mitigations]

## Start Here — Tomorrow Morning
The single most important action to take in the next 24 hours, stated in one sentence.

Write to ${FINAL} using write_file"

echo ""
echo "══════════════════════════════════════════"
echo "  REVENUE HUNT COMPLETE"
echo "══════════════════════════════════════════"
echo ""
echo "  Artifacts:"
echo "  ├── Opportunities   : $OPPORTUNITIES"
echo "  ├── Financial models: $FINANCIAL_MODELS"
echo "  ├── Competitive      : $COMPETITIVE"
echo "  ├── Winner           : $WINNER"
echo "  ├── GTM plan         : $GTM"
echo "  ├── Outreach copy    : $OUTREACH"
echo "  ├── Landing page     : $LANDING"
echo "  ├── Pricing          : $PRICING"
echo "  ├── Objections       : $OBJECTIONS"
echo "  └── FULL PACKAGE     : $FINAL"
echo ""
echo "  Start here: $FINAL"
