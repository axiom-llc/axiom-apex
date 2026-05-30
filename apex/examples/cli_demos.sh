#!/usr/bin/env bash
# autonomous-business.sh — A complete operating day, unattended
# Models a solo service business running itself from open to close:
# inbound triage → lead qualification → proposal dispatch →
# project delivery checks → invoice follow-up → EOD P&L
#
# No human in the loop. Run it at 07:00. Read the report at 17:00.
#
# Usage: ./autonomous-business.sh [business_profile] [date_override]
# Example: ./autonomous-business.sh ~/.config/apex/business_profile.txt

set -euo pipefail

PROFILE="${1:-${HOME}/.config/apex/business_profile.txt}"
DATE="${2:-$(date +%Y-%m-%d)}"
DOW=$(date +%A)

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="$HOME/business/$(date +%Y%m%d)"
LOG="$OUTDIR/ops.log"
EOD_REPORT="$OUTDIR/eod-report.md"
PNL="$OUTDIR/pnl-snapshot.txt"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"/{inbound,leads,proposals,projects,invoices,comms,decisions}

echo "▶ Date    : $DATE ($DOW)"
echo "▶ Output  : $OUTDIR"
echo ""

# ── Load business context ─────────────────────────────────
if [[ -f "$PROFILE" ]]; then
    BIZ_CONTEXT=$(cat "$PROFILE")
else
    BIZ_CONTEXT="Solo AI automation consultancy. Services: workflow automation, LLM integration, backend systems. Rate: \$150/hr. Target clients: SMBs and startups. Current capacity: available for new work."
fi

log() { echo "[$(date +%H:%M)] $*" | tee -a "$LOG"; }

# ═════════════════════════════════════════════════════════
# PHASE 1 — MORNING TRIAGE (parallel)
# Read everything that arrived overnight. Classify and prioritise.
# ═════════════════════════════════════════════════════════
log "PHASE 1: Morning triage"
echo ""

INBOUND_SUMMARY="$OUTDIR/inbound/summary.txt"
PIPELINE_SNAPSHOT="$OUTDIR/leads/pipeline-snapshot.txt"
PROJECT_HEALTH="$OUTDIR/projects/health-snapshot.txt"
CASH_POSITION="$OUTDIR/invoices/cash-position.txt"

apex "Business context: ${BIZ_CONTEXT}

Simulate overnight inbound for a solo service business on ${DATE} (${DOW}).
Generate 2-4 realistic inbound items that might arrive overnight:
- Mix of: new enquiry, reply to proposal, support question, invoice payment, referral
- Each should feel like a real message with realistic sender names and content
- At least one should require same-day action

Write each item with: TYPE | FROM | SUBJECT | BODY | URGENCY: HIGH/MEDIUM/LOW
Write to ${INBOUND_SUMMARY} using write_file" &

apex "Business context: ${BIZ_CONTEXT}

Simulate the current sales pipeline state for ${DATE}.
Generate a realistic pipeline with 4-6 leads at different stages:
STAGE: NEW | QUALIFIED | PROPOSAL_SENT | NEGOTIATING | CLOSED_WON | CLOSED_LOST
Include: lead name, company, deal value, days in current stage, last contact date

Flag any leads stalled 5+ days with no movement.
Write pipeline to ${PIPELINE_SNAPSHOT} using write_file" &

apex "Business context: ${BIZ_CONTEXT}

Simulate active project health for ${DATE}.
Generate 2-3 active client projects with realistic status:
Include: project name, client, % complete, next deliverable, due date, hours logged vs estimated
Flag: ON_TRACK | AT_RISK | OVERDUE

Write project health to ${PROJECT_HEALTH} using write_file" &

apex "Business context: ${BIZ_CONTEXT}

Simulate current cash position for ${DATE}.
Generate realistic receivables and payables:
- Outstanding invoices: 2-3 with amounts, issue dates, due dates, status
- Monthly recurring costs: hosting, tools, subscriptions
- Cash on hand estimate
- 30-day revenue forecast based on pipeline

Write cash position to ${CASH_POSITION} using write_file" &

log "  waiting for triage agents..."
wait
log "  triage complete"
echo ""

# ═════════════════════════════════════════════════════════
# PHASE 2 — DECISION ENGINE
# Read all triage output. Produce a prioritised action plan.
# This is the brain of the operating day.
# ═════════════════════════════════════════════════════════
log "PHASE 2: Decision engine"

DAILY_PLAN="$OUTDIR/decisions/daily-plan.txt"

apex "You are the operating intelligence for a solo service business.
Business context: ${BIZ_CONTEXT}
Date: ${DATE} (${DOW})

Read today's situation using read_file:
- Inbound: ${INBOUND_SUMMARY}
- Pipeline: ${PIPELINE_SNAPSHOT}
- Projects: ${PROJECT_HEALTH}
- Cash: ${CASH_POSITION}

Produce a prioritised operating plan for today. For each action:
PRIORITY (1-10) | ACTION_TYPE | TARGET | WHAT TO DO | EXPECTED OUTCOME

Action types: RESPOND | QUALIFY | PROPOSE | FOLLOW_UP | DELIVER | INVOICE | DEFER | IGNORE

Rules:
- Revenue-protecting actions rank highest (invoice follow-up, closing negotiating deals)
- Never defer a HIGH urgency inbound item
- If cash position shows overdue invoices, escalate follow-up priority
- AT_RISK or OVERDUE projects get a delivery check before any sales activity
- Maximum 6 actions — ruthlessly prioritise

Write the ordered action plan to ${DAILY_PLAN} using write_file"

log "  daily plan generated"
echo ""
cat "$DAILY_PLAN"
echo ""

# ═════════════════════════════════════════════════════════
# PHASE 3 — EXECUTION
# Execute each action in the plan in parallel where possible.
# ═════════════════════════════════════════════════════════
log "PHASE 3: Executing actions"

# Action 1: Respond to high-urgency inbound
apex "Read the inbound summary at ${INBOUND_SUMMARY} using read_file.
Read the daily plan at ${DAILY_PLAN} using read_file.

Identify all HIGH urgency inbound items.
For each: draft a professional, human-sounding response under 120 words.
Reference specific details from their message — do not sound templated.

Write all response drafts to ${OUTDIR}/comms/inbound-responses-${DATE}.txt
using write_file" &

# Action 2: Work the pipeline — qualify new leads + follow up stalled ones
apex "Read the pipeline snapshot at ${PIPELINE_SNAPSHOT} using read_file.
Read the business context: ${BIZ_CONTEXT}

For each NEW lead: produce a qualification assessment (fit score 1-10, budget signals, recommended action)
For each lead stalled 5+ days: draft a follow-up message under 80 words
For any NEGOTIATING lead: draft a gentle close or next-step nudge

Write all pipeline actions to ${OUTDIR}/leads/pipeline-actions-${DATE}.txt
using write_file" &

# Action 3: Project delivery check + client update
apex "Read the project health at ${PROJECT_HEALTH} using read_file.

For each AT_RISK or OVERDUE project: draft a proactive client status update
that acknowledges the situation without alarming the client, states the revised
timeline, and requests any blockers be resolved.

For ON_TRACK projects due a milestone this week: draft a brief progress update.

Write all project comms to ${OUTDIR}/projects/client-updates-${DATE}.txt
using write_file" &

# Action 4: Invoice follow-up
apex "Read the cash position at ${CASH_POSITION} using read_file.

For each overdue invoice: draft a payment follow-up.
- 1-14 days overdue: friendly reminder
- 15-29 days overdue: firm reminder with specific payment request
- 30+ days overdue: formal demand with payment deadline

For invoices due within 7 days: draft a courtesy heads-up.

Write all invoice comms to ${OUTDIR}/invoices/follow-ups-${DATE}.txt
using write_file" &

log "  waiting for execution agents..."
wait
log "  execution complete"
echo ""

# ═════════════════════════════════════════════════════════
# PHASE 4 — PROPOSAL GENERATION
# If any qualified leads were identified, generate proposals.
# Runs after execution so qualification output is available.
# ═════════════════════════════════════════════════════════
log "PHASE 4: Proposal generation"

QUALIFIED_LEADS="$OUTDIR/leads/pipeline-actions-${DATE}.txt"

apex "Read the pipeline actions at ${QUALIFIED_LEADS} using read_file.
Business context: ${BIZ_CONTEXT}

Identify any leads recommended for PROPOSE.

For each: write a concise project proposal:
- Executive summary (2 sentences)
- Scope of work (specific deliverables, clear exclusions)
- Timeline (phases with milestones)
- Investment (fixed fee or hourly estimate)
- Single CTA

Under 500 words per proposal. Direct and confident — no boilerplate.

Write all proposals to ${OUTDIR}/proposals/proposals-${DATE}.txt using write_file"

log "  proposals generated"
echo ""

# ═════════════════════════════════════════════════════════
# PHASE 5 — EOD RECONCILIATION + P&L SNAPSHOT
# Read everything that happened today. Produce the EOD report.
# ═════════════════════════════════════════════════════════
log "PHASE 5: EOD reconciliation"

apex "You are producing the end-of-day operating report for a solo service business.
Business context: ${BIZ_CONTEXT}
Date: ${DATE} (${DOW})

Read all of today's outputs using read_file:
${INBOUND_SUMMARY}
${PIPELINE_SNAPSHOT}
${PROJECT_HEALTH}
${CASH_POSITION}
${DAILY_PLAN}
${OUTDIR}/comms/inbound-responses-${DATE}.txt
${OUTDIR}/leads/pipeline-actions-${DATE}.txt
${OUTDIR}/projects/client-updates-${DATE}.txt
${OUTDIR}/invoices/follow-ups-${DATE}.txt
${OUTDIR}/proposals/proposals-${DATE}.txt

Write a complete EOD report in Markdown:

# Operating Report — ${DATE}

## Day Summary
(3 sentences: what happened today, what moved, what got done)

## Actions Taken
(table: Action | Target | Status | Expected Outcome)

## Pipeline Movement
(leads advanced, stalled, closed — net pipeline value change)

## Revenue Activity
(invoices followed up, proposals sent, deals closed — total value in motion)

## Project Status
(each active project: status change if any, next milestone)

## Cash Position
(receivables outstanding, overdue amounts, 30-day forecast)

## Tomorrow's Priorities
(top 3 actions ranked by revenue impact)

## Decisions Made
(any leads deferred, ignored, or disqualified — with rationale)

Write to ${EOD_REPORT} using write_file"

# P&L snapshot — separate file, numbers only
apex "Read the cash position at ${CASH_POSITION} and the EOD report
at ${EOD_REPORT} using read_file.

Extract a plain-text P&L snapshot for ${DATE}:
RECEIVABLES OUTSTANDING: total \$
OVERDUE (30+ days): total \$
PROPOSALS IN FLIGHT: count and total potential value \$
PIPELINE VALUE: total qualified pipeline \$
MONTHLY RECURRING COSTS: \$
30-DAY REVENUE FORECAST: \$
RUNWAY ESTIMATE: X months at current burn

Numbers only — no prose.
Write to ${PNL} using write_file"

log "  EOD reconciliation complete"
echo ""

# ═════════════════════════════════════════════════════════
# OUTPUT
# ═════════════════════════════════════════════════════════
echo "══════════════════════════════════════════"
echo "  AUTONOMOUS BUSINESS — ${DATE}"
echo "══════════════════════════════════════════"
echo ""
cat "$EOD_REPORT"
echo ""
echo "── P&L Snapshot ──"
cat "$PNL"
echo ""
echo "✓ Operating day complete"
echo "  Full output : $OUTDIR"
echo "  EOD report  : $EOD_REPORT"
echo "  Ops log     : $LOG"
#!/usr/bin/env bash
# code-review.sh — AI-driven multi-pass code review agent
# Performs layered static analysis: correctness → security → style → optimisation
# Produces per-file annotations and a consolidated review report
# Usage: ./code-review.sh <target_dir> [file_glob]
# Example: ./code-review.sh ~/myproject "*.py"

set -euo pipefail

TARGET_DIR="${1:-$PWD}"
GLOB="${2:-"*.py"}"

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="$HOME/code-review/$(date +%Y%m%d_%H%M%S)"
REPORT="$OUTDIR/review.md"
SUMMARY="$OUTDIR/summary.txt"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Target : $TARGET_DIR"
echo "▶ Glob   : $GLOB"
echo "▶ Output : $OUTDIR"
echo ""

# ── Discover files ────────────────────────────────────────────────────────────
mapfile -t FILES < <(find "$TARGET_DIR" -maxdepth 4 -name "$GLOB" \
    ! -path "*/.*" ! -path "*/__pycache__/*" ! -path "*/venv/*" ! -path "*/.venv/*" \
    | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "✗ No files matched '$GLOB' in $TARGET_DIR"
    exit 1
fi

echo "── Found ${#FILES[@]} file(s):"
printf '   %s\n' "${FILES[@]}"
echo ""

REVIEW_LAYERS=("correctness: logic errors, edge cases, undefined behaviour, incorrect assumptions"
               "security: injection vectors, unsafe defaults, hardcoded secrets, improper validation"
               "quality: naming, complexity, dead code, missing error handling, test coverage gaps")

# ── Per-file review ───────────────────────────────────────────────────────────
for FILE in "${FILES[@]}"; do
    BASENAME=$(basename "$FILE")
    FILE_OUT="$OUTDIR/review_${BASENAME}.md"

    echo "── Reviewing: $BASENAME"

    for LAYER in "${REVIEW_LAYERS[@]}"; do
        LAYER_NAME="${LAYER%%:*}"
        echo "   → $LAYER_NAME"
    done

    apex "You are a senior code reviewer performing a structured multi-layer review.

Read the file at ${FILE} using read_file.

Perform a rigorous review across these three layers in order:
$(printf '%s\n' "${REVIEW_LAYERS[@]}")

For each issue found, output:
- LAYER: (correctness|security|quality)
- SEVERITY: (critical|high|medium|low)
- LINE: (line number or range, if determinable)
- ISSUE: one-sentence description
- FIX: concrete corrective action or rewritten snippet

If a layer has no issues, write: [layer name]: PASS

End with a VERDICT section:
- Overall quality score 1–10
- One sentence on the single highest-priority fix
- Estimated refactor effort: (trivial|hours|days)

Write as clean Markdown to ${FILE_OUT} using write_file"

    [[ -f "$FILE_OUT" ]] && echo "   ✓ $BASENAME done" || echo "   ⚠ no output for $BASENAME"
done

# ── Cross-file analysis ───────────────────────────────────────────────────────
echo ""
echo "── Cross-file analysis..."
COMBINED="$OUTDIR/combined_reviews.txt"
> "$COMBINED"

for FILE in "${FILES[@]}"; do
    BASENAME=$(basename "$FILE")
    FILE_OUT="$OUTDIR/review_${BASENAME}.md"
    if [[ -f "$FILE_OUT" ]]; then
        echo "=== $BASENAME ===" >> "$COMBINED"
        cat "$FILE_OUT" >> "$COMBINED"
        echo "" >> "$COMBINED"
    fi
done

apex "You are a lead engineer synthesising individual file reviews into a project-wide assessment.

Read the combined per-file reviews using read_file from ${COMBINED}

Produce a consolidated Markdown report with these sections:

# Code Review — $(basename "$TARGET_DIR")
## Executive Summary
(3–5 sentences: overall quality, dominant risk, recommended first action)

## Critical & High Issues
(table: File | Line | Severity | Issue | Recommended Fix)

## Patterns & Systemic Issues
(issues appearing across multiple files — root causes, not symptoms)

## Security Assessment
(dedicated section: attack surface, trust boundaries, highest-risk vectors)

## Refactor Roadmap
(prioritised list: what to fix first, rough effort, expected impact)

## Metrics
(counts by severity across all files; overall score average)

Rules:
- Specific and actionable throughout — no generic advice
- Reference actual file names and line numbers from the reviews
- Order all lists by severity descending

Write to ${REPORT} using write_file"

# ── Spoken summary ────────────────────────────────────────────────────────────
echo ""
echo "── Generating spoken summary..."

apex "Read the code review report using read_file from ${REPORT}

Extract a 2–3 sentence spoken summary suitable for espeak:
- Total files reviewed
- Number of critical/high issues
- Single most important action

Write only the plain text sentences (no markdown) to ${SUMMARY} using write_file"

if [[ -f "$SUMMARY" ]]; then
    espeak-ng "$(cat "$SUMMARY")" 2>/dev/null || true
fi

echo ""
echo "✓ Done"
echo "  Per-file  : $OUTDIR/review_*.md"
echo "  Report    : $REPORT"
#!/usr/bin/env bash
# competitive-intelligence-swarm.sh — Parallel competitive intelligence agent
# Axiom LLC — https://github.com/axiom-llc/apex
#
# Spawns N agents across orthogonal competitive dimensions:
# positioning, pricing, product, sentiment, hiring signals, technology stack.
# Synthesises findings into a structured strategic brief.
#
# Demonstrates: parallel market research, signal extraction, strategic synthesis
#
# Usage: ./competitive-intelligence-swarm.sh "company or product" [agents] [iterations]
# Example: ./competitive-intelligence-swarm.sh "Vercel" 5 6

set -euo pipefail

TARGET="${1:-}"
AGENTS="${2:-5}"
ITER="${3:-6}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 \"target company or product\" [agents] [iterations]"
    exit 1
fi

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_SCRIPT="${AGENT_SCRIPT:-$(dirname "$0")/research-agent.sh}"
OUTDIR="$HOME/competitive-intel/$(date +%Y%m%d_%H%M%S)"
GOALSFILE="$OUTDIR/dimensions.txt"
BRIEF="$OUTDIR/brief.md"
SUMMARY="$OUTDIR/summary.txt"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Target     : $TARGET"
echo "▶ Agents     : $AGENTS"
echo "▶ Iter/agent : $ITER"
echo "▶ Output     : $OUTDIR"
echo ""

espeak-ng "Starting competitive intelligence swarm on ${TARGET}" 2>/dev/null || true

# ── Generate research dimensions ──────────────────────────────────────────────
echo "── Generating competitive dimensions..."

apex "You are a strategic intelligence analyst preparing a competitive research brief on: ${TARGET}

Decompose the competitive landscape into exactly ${AGENTS} orthogonal research dimensions.
Each dimension should be independently researchable and collectively give full coverage.

Draw from these angle categories (select the most relevant ${AGENTS}):
- Market positioning and messaging strategy
- Pricing model, packaging tiers, and value proposition
- Product capabilities, roadmap signals, and feature differentiation
- Developer and user community sentiment (forums, HN, Reddit, reviews)
- Hiring patterns as a signal of strategic investment areas
- Technology stack, infrastructure choices, and engineering culture
- Partnerships, integrations, and ecosystem play
- Funding history, valuation signals, and investor thesis
- Content and SEO strategy — what topics they own
- Known weaknesses, churn signals, and customer complaints

Output exactly ${AGENTS} lines. One dimension per line.
Each line: a specific, actionable research sub-goal for ${TARGET}.
No numbering, no bullets.
Write to ${GOALSFILE} using write_file"

[[ ! -f "$GOALSFILE" ]] && echo "✗ Dimension generation failed" && exit 1

echo "── Research dimensions:"
cat -n "$GOALSFILE"
echo ""

# ── Launch parallel agents ────────────────────────────────────────────────────
echo "── Launching ${AGENTS} agents in parallel..."

PIDS=()
i=0
while IFS= read -r dimension; do
    [[ -z "$dimension" ]] && continue
    AGENT_OUT="$OUTDIR/agent_${i}"
    mkdir -p "$AGENT_OUT"

    (
        export OUTDIR_OVERRIDE="$AGENT_OUT"
        bash "$AGENT_SCRIPT" "$dimension" "$ITER" 2>&1 | \
            sed "s/^/  [intel_${i}] /"
    ) &

    PIDS+=($!)
    echo "   agent_${i} (pid ${PIDS[-1]}): $dimension"
    i=$((i+1))
done < "$GOALSFILE"

echo ""
echo "── Waiting for ${#PIDS[@]} agents..."
for pid in "${PIDS[@]}"; do
    wait "$pid" && echo "   ✓ pid $pid" || echo "   ⚠ pid $pid exited non-zero"
done

# ── Collect reports ───────────────────────────────────────────────────────────
echo ""
echo "── Collecting agent reports..."
COMBINED="$OUTDIR/combined.txt"
> "$COMBINED"

for j in $(seq 0 $((AGENTS-1))); do
    AGENT_REPORT=$(find "$OUTDIR/agent_${j}" -name "report.md" 2>/dev/null | head -1)
    if [[ -f "$AGENT_REPORT" ]]; then
        echo "=== DIMENSION ${j} ===" >> "$COMBINED"
        cat "$AGENT_REPORT" >> "$COMBINED"
        echo "" >> "$COMBINED"
        echo "   ✓ agent_${j} collected"
    else
        echo "   ⚠ agent_${j} no report"
    fi
done

# ── Strategic synthesis ───────────────────────────────────────────────────────
echo ""
echo "── Synthesising strategic brief..."

RESEARCH_DATE=$(date +"%B %d, %Y")

apex "You are a principal analyst at a strategy consultancy synthesising a competitive brief.
Subject: ${TARGET}
Research date: ${RESEARCH_DATE}

Read the combined agent findings using read_file from ${COMBINED}

Produce a structured strategic intelligence brief in Markdown:

# Competitive Intelligence Brief: ${TARGET}
**Date:** ${RESEARCH_DATE}
**Prepared by:** Axiom LLC

## Executive Summary
(4–6 sentences: who they are, their current trajectory, primary threat/opportunity vector,
and the single most actionable insight for a competitor or investor)

## Market Position & Messaging
(how they frame themselves, who they target, what narrative they own)

## Product & Capabilities
(what they actually do well, key differentiators, notable gaps)

## Pricing & Business Model
(structure, tiers, where they extract value, any predatory or lock-in mechanics)

## Community & Sentiment
(developer/user perception, vocal complaints, loyalty signals, NPS proxies)

## Strategic Signals
(hiring patterns, partnerships, content bets, infrastructure choices — what do these
suggest about their 12–18 month direction?)

## Vulnerabilities & Attack Surface
(where a competitor could credibly win — underserved segments, weak product areas,
pricing pressure points, trust gaps)

## Recommended Watch Items
(3–5 specific signals to monitor going forward, with rationale)

---
*This brief was generated by an autonomous research swarm and is intended as a
structured starting point for human analyst review.*

Rules:
- Specific throughout — company names, product names, numbers, dates
- Resolve conflicts between agents — note genuine disagreement where it exists
- No padding, no generic strategy-speak
- Integrate signals across dimensions — find cross-cutting patterns agents missed individually

Write to ${BRIEF} using write_file"

# ── Spoken summary ────────────────────────────────────────────────────────────
echo ""
echo "── Spoken summary..."

apex "Read the brief using read_file from ${BRIEF}

Extract a 2-sentence spoken summary covering:
- The single most important finding about ${TARGET}
- The top recommended action or watch item

Plain text only, no markdown.
Write to ${SUMMARY} using write_file"

if [[ -f "$SUMMARY" ]]; then
    espeak-ng "$(cat "$SUMMARY")" 2>/dev/null || true
fi

echo ""
echo "✓ Swarm complete"
echo "  Dimensions  : $GOALSFILE"
echo "  Agent dirs  : $OUTDIR/agent_*"
echo "  Combined    : $COMBINED"
echo "  Brief       : $BRIEF"
#!/usr/bin/env bash
# iterative-coder.sh — Write, run, fix loop
# APEX writes code, executes it, reads errors, fixes, repeats until passing.
# Usage: ./iterative-coder.sh "task description" [max_iterations]
# Example: ./iterative-coder.sh "write a python script that finds prime numbers up to N" 8

set -euo pipefail

TASK="${1:-}"
MAX_ITER="${2:-8}"

[[ -z "$TASK" ]] && echo "Usage: $0 \"task\" [max_iterations]" && exit 1

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="$HOME/coder/$(date +%Y%m%d_%H%M%S)"
OUTPUT="$OUTDIR/solution.py"
LOG="$OUTDIR/run.log"
REPORT="$OUTDIR/report.md"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Task    : $TASK"
echo "▶ Max iter: $MAX_ITER"
echo "▶ Output  : $OUTPUT"
echo ""

# ── Iteration 0: initial generation ──────────────────────
echo "── [0] Generating initial solution..."

apex "You are an expert Python engineer. Write a complete, runnable Python script for:
${TASK}

Requirements:
- Handles edge cases and invalid input
- Includes a __main__ block with test cases that print PASS/FAIL
- No external dependencies beyond stdlib
- Production quality — not a demo

Write only the Python file to ${OUTPUT} using write_file"

[[ ! -f "$OUTPUT" ]] && echo "✗ Initial generation failed" && exit 1

# ── Fix loop ──────────────────────────────────────────────
for i in $(seq 1 "$MAX_ITER"); do

    echo "── [$i] Running..."
    python3 "$OUTPUT" > "$LOG" 2>&1
    EXIT=$?

    if [[ $EXIT -eq 0 ]]; then
        echo "   ✓ All tests passing at iteration $i"
        break
    fi

    echo "   ✗ Exit $EXIT — fixing..."

    apex "You are debugging a Python script.

Task the script was written for:
${TASK}

Read the current script at ${OUTPUT} using read_file.

Error output:
$(cat "$LOG")

Diagnose the root cause. Fix all errors. Do not change correct behaviour.
Write the corrected script back to ${OUTPUT} using write_file"

done

# ── Final report ──────────────────────────────────────────
python3 "$OUTPUT" > "$LOG" 2>&1 && FINAL_EXIT=0 || FINAL_EXIT=$?

apex "Read the final script at ${OUTPUT} using read_file.

Write a brief technical report in Markdown covering:
- What the script does
- Iterations required to reach passing state
- Final test result: $( [[ $FINAL_EXIT -eq 0 ]] && echo PASS || echo FAIL )
- Any remaining issues or limitations

Write to ${REPORT} using write_file"

echo ""
echo "✓ Done"
echo "  Solution : $OUTPUT"
echo "  Log      : $LOG"
echo "  Report   : $REPORT"
#!/usr/bin/env bash
# parallel-swarm.sh — N-agent parallel research swarm
# Decomposes any topic into orthogonal dimensions, runs agents in parallel,
# synthesises findings into a structured report.
# Usage: ./parallel-swarm.sh "topic" [agents] [iterations_per_agent]
# Example: ./parallel-swarm.sh "the current state of fusion energy" 5 8

set -euo pipefail

TOPIC="${1:-}"
AGENTS="${2:-5}"
ITER="${3:-8}"

[[ -z "$TOPIC" ]] && echo "Usage: $0 \"topic\" [agents] [iterations]" && exit 1

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_SCRIPT="$(dirname "$0")/research-agent.sh"
OUTDIR="$HOME/swarm/$(date +%Y%m%d_%H%M%S)"
DIMENSIONS="$OUTDIR/dimensions.txt"
COMBINED="$OUTDIR/combined.txt"
REPORT="$OUTDIR/report.md"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Topic   : $TOPIC"
echo "▶ Agents  : $AGENTS"
echo "▶ Iter    : $ITER"
echo "▶ Output  : $OUTDIR"
echo ""

# ── Decompose topic into research dimensions ──────────────
echo "── Decomposing topic..."

apex "You are a research director decomposing a topic for a parallel research swarm.

Topic: ${TOPIC}

Generate exactly ${AGENTS} orthogonal research dimensions.
Each dimension must be independently researchable.
Collectively they must give complete coverage of the topic.
Each dimension should be a specific, concrete research question.

Output exactly ${AGENTS} lines. One dimension per line. No numbering, no bullets.
Write to ${DIMENSIONS} using write_file"

[[ ! -f "$DIMENSIONS" ]] && echo "✗ Decomposition failed" && exit 1

echo "── Dimensions:"
cat -n "$DIMENSIONS"
echo ""

# ── Launch parallel agents ────────────────────────────────
echo "── Launching ${AGENTS} agents..."

PIDS=()
i=0
while IFS= read -r dimension; do
    [[ -z "$dimension" ]] && continue
    AGENT_OUT="$OUTDIR/agent_${i}"
    mkdir -p "$AGENT_OUT"
    (
        export OUTDIR_OVERRIDE="$AGENT_OUT"
        bash "$AGENT_SCRIPT" "$dimension" "$ITER" 2>&1 | sed "s/^/  [agent_${i}] /"
    ) &
    PIDS+=($!)
    echo "   agent_${i} (pid ${PIDS[-1]}): $dimension"
    i=$((i+1))
done < "$DIMENSIONS"

echo ""
echo "── Waiting for ${#PIDS[@]} agents..."
for pid in "${PIDS[@]}"; do
    wait "$pid" && echo "   ✓ pid $pid" || echo "   ⚠ pid $pid exited non-zero"
done

# ── Collect reports ───────────────────────────────────────
echo ""
echo "── Collecting reports..."
> "$COMBINED"

for j in $(seq 0 $((AGENTS-1))); do
    AGENT_REPORT=$(find "$OUTDIR/agent_${j}" -name "report.md" 2>/dev/null | head -1)
    if [[ -f "$AGENT_REPORT" ]]; then
        echo "=== DIMENSION ${j} ===" >> "$COMBINED"
        cat "$AGENT_REPORT" >> "$COMBINED"
        echo "" >> "$COMBINED"
        echo "   ✓ agent_${j}"
    else
        echo "   ⚠ agent_${j} — no report"
    fi
done

# ── Synthesis ─────────────────────────────────────────────
echo ""
echo "── Synthesising..."

apex "You are a senior analyst synthesising parallel research into a unified report.

Topic: ${TOPIC}

Read the combined agent findings using read_file from ${COMBINED}

Write a comprehensive Markdown report structured around the topic — choose headers
that fit the content, not a fixed template. Requirements:
- Integrate findings across dimensions — surface cross-cutting patterns
- Resolve contradictions between agents (prefer the more specific claim)
- Concrete throughout: names, numbers, dates, mechanisms
- No meta-commentary about the research process
- End with: Key Findings (5 bullets) and Open Questions (3 bullets)

Write to ${REPORT} using write_file"

echo ""
echo "✓ Swarm complete"
echo "  Dimensions : $DIMENSIONS"
echo "  Agents     : $OUTDIR/agent_*"
echo "  Report     : $REPORT"
#!/usr/bin/env bash
# recursive-self-improvement-swarm.sh — Apex rewrites itself
# A pipeline of 5 sequential agents: critique → propose → implement → test → diff
# Each generation's output becomes the next generation's input codebase.
# Runs until no improvements are proposed or an unfixable regression is detected.
#
# Usage: ./recursive-self-improvement-swarm.sh [max_generations] [apex_src]
# Example: ./recursive-self-improvement-swarm.sh 5 ~/code/apps/axiom-apex

set -euo pipefail

MAX_GEN="${1:-5}"
APEX_SRC="${2:-$(cd "$(dirname "$0")/.." && pwd)}"
APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

OUTDIR="$HOME/swarm/rsi/$(date +%Y%m%d_%H%M%S)"
GENLOG="$OUTDIR/generation_log.md"
mkdir -p "$OUTDIR"

cd "$APEX_ROOT"

echo "▶ Max generations : $MAX_GEN"
echo "▶ Apex source     : $APEX_SRC"
echo "▶ Output          : $OUTDIR"
echo ""

# Seed: copy current apex source as generation 0
GEN_SRC="$OUTDIR/gen_0/src"
mkdir -p "$GEN_SRC"
cp -r "$APEX_SRC/." "$GEN_SRC/"
echo "── Generation 0: seeded from $APEX_SRC"

echo "# RSI Swarm — $(date)" > "$GENLOG"
echo "" >> "$GENLOG"

# ── Main loop ─────────────────────────────────────────────────────────────────
for GEN in $(seq 1 "$MAX_GEN"); do
    PREV_SRC="$OUTDIR/gen_$((GEN-1))/src"
    GENDIR="$OUTDIR/gen_${GEN}"
    mkdir -p "$GENDIR"

    CRITIQUE="$GENDIR/critique.md"
    PROPOSAL="$GENDIR/proposal.md"
    NEXT_SRC="$GENDIR/src"
    TEST_REPORT="$GENDIR/test_report.md"
    CHANGELOG="$GENDIR/changelog.md"

    cp -r "$PREV_SRC/." "$NEXT_SRC/"

    echo ""
    echo "══════════════════════════════════════════"
    echo "  GENERATION ${GEN} / ${MAX_GEN}"
    echo "══════════════════════════════════════════"
    echo "## Generation ${GEN}" >> "$GENLOG"

    # ── Agent 1: Critique ──────────────────────────────────────────────────────
    echo ""
    echo "── [Agent 1] Critiquing architecture..."

    apex "You are a senior systems architect performing a brutal, honest code review.

Read every Python file inside ${PREV_SRC}/apex/ using read_file.
Also read ${PREV_SRC}/README.md if it exists.

Produce a structured critique covering:
- Architectural flaws or violations of the stated design axioms
- Functions or modules that are doing too much or too little
- Abstraction leaks or implicit coupling between components
- Missing error handling or edge cases
- Performance inefficiencies
- Any dead code or redundant logic
- Specific, concrete improvement opportunities (not vague suggestions)

Be surgical. Every point must cite the exact file and line range it refers to.
No praise. No summary of what the code does. Flaws only.

Write to ${CRITIQUE} using write_file"

    if [[ ! -f "$CRITIQUE" ]]; then
        echo "✗ Agent 1 failed — aborting generation ${GEN}"
        break
    fi

    # Check if critique is substantive
    CRITIQUE_LINES=$(wc -l < "$CRITIQUE")
    if [[ "$CRITIQUE_LINES" -lt 5 ]]; then
        echo "✓ No meaningful critique produced — apex has converged after $((GEN-1)) generations"
        echo "**Converged.** No further improvements identified." >> "$GENLOG"
        break
    fi

    echo "   ✓ Critique written ($CRITIQUE_LINES lines)"

    # ── Agent 2: Propose ───────────────────────────────────────────────────────
    echo ""
    echo "── [Agent 2] Proposing concrete changes..."

    apex "You are a principal engineer. You have received a code critique and must propose fixes.

Read the critique at ${CRITIQUE} using read_file.
Read the relevant source files in ${PREV_SRC}/apex/ using read_file as needed.

Produce a concrete change proposal:
- For each critique point, propose the exact change to make
- Specify: which file, which function/class, what to change and how
- If a critique point is wrong or not worth fixing, say so explicitly and skip it
- Order proposals by impact (highest first)
- Flag any proposal that risks breaking existing behaviour as [RISKY]

Be specific enough that another engineer could implement each point without asking questions.
No code yet — prose descriptions of changes only.

Write to ${PROPOSAL} using write_file"

    if [[ ! -f "$PROPOSAL" ]]; then
        echo "✗ Agent 2 failed — aborting generation ${GEN}"
        break
    fi

    PROPOSAL_LINES=$(wc -l < "$PROPOSAL")
    echo "   ✓ Proposal written ($PROPOSAL_LINES lines)"

    # ── Agent 3: Implement ─────────────────────────────────────────────────────
    echo ""
    echo "── [Agent 3] Implementing changes..."

    apex "You are an expert Python engineer. Implement the proposed changes exactly.

Read the proposal at ${PROPOSAL} using read_file.
Read the source files in ${NEXT_SRC}/apex/ using read_file as needed.

For each proposal:
- Implement it by writing the updated file back to ${NEXT_SRC}/apex/<filename> using write_file
- Skip any proposal marked [RISKY] — do not implement it
- Do not change any file not mentioned in the proposal
- Do not alter the external CLI interface or tool signatures
- Preserve all existing comments and docstrings unless they are wrong

After implementing, write a one-line summary of each change actually made.
Write this implementation summary to ${GENDIR}/impl_summary.txt using write_file"

    echo "   ✓ Implementation complete"

    # ── Agent 4: Test ──────────────────────────────────────────────────────────
    echo ""
    echo "── [Agent 4] Running regression tests..."

    # Run actual tests if they exist
    TEST_EXIT=0
    if [[ -f "$NEXT_SRC/apex/tests/test_apex.py" ]]; then
        cd "$NEXT_SRC"
        python3 -m pytest apex/tests/ --tb=short -q > "$GENDIR/pytest_raw.txt" 2>&1 || TEST_EXIT=$?
        cd "$APEX_ROOT"
    fi

    apex "You are a QA engineer reviewing the result of a code change.

Read the change proposal at ${PROPOSAL} using read_file.
Read the implementation summary at ${GENDIR}/impl_summary.txt using read_file if it exists.
$([ -f "$GENDIR/pytest_raw.txt" ] && echo "Read the raw test output at ${GENDIR}/pytest_raw.txt using read_file."  || echo "No automated test output is available.")
Read the updated source in ${NEXT_SRC}/apex/ using read_file.

Produce a test report covering:
- Which changes were implemented correctly
- Any logic errors introduced by the implementation
- Any regressions detected (real or suspected)
- An overall verdict: PASS, WARN (minor issues), or FAIL (regression detected)
- If FAIL: exactly what must be reverted and why

Write to ${TEST_REPORT} using write_file"

    if [[ ! -f "$TEST_REPORT" ]]; then
        echo "✗ Agent 4 failed — aborting generation ${GEN}"
        break
    fi

    VERDICT=$(grep -oE "^(PASS|WARN|FAIL)" "$TEST_REPORT" 2>/dev/null | head -1 || echo "UNKNOWN")
    echo "   ✓ Test report written — verdict: $VERDICT"

    if [[ "$VERDICT" == "FAIL" ]]; then
        echo ""
        echo "✗ Regression detected in generation ${GEN} — halting."
        echo "**FAIL** — regression detected. Swarm halted." >> "$GENLOG"
        echo "Reverted: keeping gen_$((GEN-1)) as last good version."
        break
    fi

    # ── Agent 5: Diff & Changelog ──────────────────────────────────────────────
    echo ""
    echo "── [Agent 5] Writing changelog..."

    # Generate raw diff
    diff -rq --exclude="*.pyc" --exclude="__pycache__" \
        "$PREV_SRC/apex/" "$NEXT_SRC/apex/" > "$GENDIR/raw.diff" 2>&1 || true

    apex "You are a technical writer producing a changelog entry.

Read the raw diff at ${GENDIR}/raw.diff using read_file.
Read the test report at ${TEST_REPORT} using read_file.
Read the proposal at ${PROPOSAL} using read_file.

Write a concise, precise changelog entry in Markdown for generation ${GEN}:
- One-line summary of what changed and why
- Bullet list of specific changes (file, what changed, effect)
- Verdict and any warnings from the test report
- Mark any change that was skipped or reverted

Write to ${CHANGELOG} using write_file"

    cat "$CHANGELOG" >> "$GENLOG"
    echo "" >> "$GENLOG"
    echo "   ✓ Changelog written"

    echo ""
    echo "✓ Generation ${GEN} complete — verdict: ${VERDICT}"
    echo "  Critique  : $CRITIQUE"
    echo "  Proposal  : $PROPOSAL"
    echo "  New src   : $NEXT_SRC"
    echo "  Tests     : $TEST_REPORT"
    echo "  Changelog : $CHANGELOG"
done

# ── Final summary ─────────────────────────────────────────────────────────────
LAST_GOOD=$(ls -d "$OUTDIR"/gen_*/src 2>/dev/null | tail -1)

echo ""
echo "══════════════════════════════════════════"
echo "  RSI SWARM COMPLETE"
echo "══════════════════════════════════════════"
echo "  Generations run : up to ${GEN}"
echo "  Last good src   : $LAST_GOOD"
echo "  Full log        : $GENLOG"
echo ""
echo "To apply the final evolved version:"
echo "  cp -r ${LAST_GOOD}/. ${APEX_SRC}/"
#!/usr/bin/env bash
# research-agent.sh — Autonomous goal-driven research agent
# The agent decides every step: SEARCH, THINK, or DONE.
# Usage: ./research-agent.sh "goal" [max_iterations]
# Example: ./research-agent.sh "produce a detailed technical explanation of how LSTMs work" 20

set -euo pipefail

GOAL="${1:-"research and explain the topic thoroughly"}"
MAX_ITER="${2:-20}"

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="${OUTDIR_OVERRIDE:-$HOME/agent/$(date +%Y%m%d_%H%M%S)}"
STATE="$OUTDIR/state.txt"
ACTIONFILE="$OUTDIR/action.txt"
REPORT="$OUTDIR/report.md"

safe_state() { cat "$STATE" | tr '"' "'"; }

# ── Available search tools (no keys required) ─────────────────────────────────
# HackerNews : https://hn.algolia.com/api/v1/search?query=TERM
# Reddit     : https://www.reddit.com/r/all/search.json?q=TERM&sort=relevance

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

# ── Bootstrap: let agent define its own goal if none given ────────────────────
FREEFORM_TRIGGERS=("self.directed" "free" "whatever" "your choice" "as you see fit" "do your own" "anything")
NORMALIZED=$(echo "$GOAL" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')
IS_FREEFORM=false
for trigger in "${FREEFORM_TRIGGERS[@]}"; do
    if [[ "$NORMALIZED" == *"$trigger"* ]]; then
        IS_FREEFORM=true
        break
    fi
done

if [[ "$IS_FREEFORM" == true ]]; then
    echo "▶ No goal specified — agent will choose its own"
    GOALFILE="$OUTDIR/goal.txt"

    apex "You are an autonomous research agent with total freedom to research any topic you find
genuinely interesting, important, or underexplored. No constraints on subject matter.

Choose a specific, substantive research goal for this session. It should be:
- A real question or topic worth investigating deeply
- Specific enough that you will know when it is satisfied
- Something that benefits from multi-source research

Output one line only: the research goal, as a clear statement or question.
Write to ${GOALFILE} using write_file"

    [[ ! -f "$GOALFILE" ]] && echo "Bootstrap failed" && exit 1
    GOAL=$(cat "$GOALFILE")
    echo "▶ Agent chose goal: $GOAL"
fi

cat > "$STATE" <<EOF
GOAL: $GOAL
---
EOF

echo "▶ Max iter: $MAX_ITER"
echo "▶ Out     : $OUTDIR"
echo ""

# ── Agent loop ────────────────────────────────────────────────────────────────
for i in $(seq 1 "$MAX_ITER"); do

    echo "── Step $i"

    apex "You are an autonomous research agent. Your goal:
${GOAL}

Current knowledge state:
$(safe_state)

---
Decide your next action. You have full freedom to act as needed to achieve the goal.
Choose ONE of the following actions and output it as the FIRST LINE of your response,
followed by your content:

ACTION: SEARCH
[URL to fetch using one of these APIs — pick the most useful one for what you need]
  HackerNews : https://hn.algolia.com/api/v1/search?query=TERM
  Reddit     : https://www.reddit.com/r/all/search.json?q=TERM&sort=relevance
[One sentence: why this search, what gap it fills]

ACTION: THINK
[150-250 words: reason over what you know, synthesise, identify gaps or contradictions]

ACTION: DONE
[Signal that the goal is sufficiently achieved and you are ready to write the final report]

Be strategic. Search when you need external data. Think when you need to reason over
what you have. Declare DONE only when you have enough to fully satisfy the goal.

Write your response to ${ACTIONFILE} using write_file"

    [[ ! -f "$ACTIONFILE" ]] && echo "  ⚠ no action file — skipping" && continue

    ACTION=$(head -1 "$ACTIONFILE" | tr -d '[:space:]' | cut -d: -f2 | tr -d '[:space:]')
    echo "   → $ACTION"

    case "$ACTION" in

        SEARCH)
            URL=$(sed -n '2p' "$ACTIONFILE" | tr -d '[:space:]')
            FETCH="$OUTDIR/fetch_${i}.txt"
            EXTRACT="$OUTDIR/extract_${i}.txt"

            if [[ -z "$URL" ]]; then
                echo "  ⚠ no URL found in action file — skipping"
                continue
            fi

            echo "     fetching: $URL"

            apex "Fetch this URL using http_get: ${URL}
Write the raw response to ${FETCH} using write_file"

            if [[ ! -f "$FETCH" ]]; then
                echo "  ⚠ fetch failed"
                echo "" >> "$STATE"
                echo "=== STEP $i: SEARCH FAILED ===" >> "$STATE"
                echo "URL: $URL" >> "$STATE"
                continue
            fi

            apex "Research goal: ${GOAL}

Current knowledge state:
$(safe_state)

Raw API response:
$(cat "$FETCH")

Extract only what is genuinely useful toward the goal.
Ignore metadata, formatting artifacts, boilerplate.
Pull out: key facts, definitions, mechanisms, names, dates, useful leads.
Note sub-topics worth investigating further.
100-200 words max, dense and specific.

Write to ${EXTRACT} using write_file"

            if [[ -f "$EXTRACT" ]]; then
                {
                    echo ""
                    echo "=== STEP $i: SEARCH ==="
                    echo "Source: $URL"
                    cat "$EXTRACT"
                } >> "$STATE"
                echo "     ✓ extracted"
            fi
            ;;

        THINK)
            THOUGHT="$OUTDIR/think_${i}.txt"

            apex "Research goal: ${GOAL}

Current knowledge state:
$(safe_state)

Your action was THINK. Write your reasoning here:
- Synthesise what you know so far
- Identify contradictions or gaps
- Decide what still needs to be found
- Note any conclusions you can draw now
150-250 words. Write to ${THOUGHT} using write_file"

            if [[ -f "$THOUGHT" ]]; then
                {
                    echo ""
                    echo "=== STEP $i: THINK ==="
                    cat "$THOUGHT"
                } >> "$STATE"
                echo "     ✓ reasoned"
            fi
            ;;

        DONE)
            echo "   ✓ agent declared done at step $i"
            break
            ;;

        *)
            echo "  ⚠ unrecognised action '$ACTION' — continuing"
            ;;
    esac

done

# ── Final report ──────────────────────────────────────────────────────────────
echo ""
echo "── Writing final report..."

apex "You are a research agent that has completed its work. The original goal:
${GOAL}

Complete knowledge state accumulated:
$(safe_state)

Write a comprehensive Markdown report that fully satisfies the original goal.
Structure it logically for the content — choose appropriate headers and sections
based on what was found, not a fixed template.

Rules:
- Resolve any contradictions (prefer specific over general)
- Concrete throughout: names, dates, numbers, mechanisms
- No meta-commentary about the research process
- No padding

Write to ${REPORT} using write_file"

echo ""
echo "✓ Complete"
echo "  State  : $STATE"
echo "  Report : $REPORT"
