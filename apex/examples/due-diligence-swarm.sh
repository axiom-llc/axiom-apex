#!/usr/bin/env bash
# due-diligence-swarm.sh — Parallel technical due diligence swarm
# Axiom LLC — https://github.com/axiom-llc/apex
#
# Performs multi-dimensional technical DD on a codebase or open-source project.
# Agents cover: architecture, security, scalability, test coverage, debt,
# dependency health, documentation, and operational readiness.
# Outputs an investor/acquirer-grade technical assessment report.
#
# Demonstrates: parallel codebase analysis, multi-dimensional synthesis,
# structured risk scoring, executive and technical dual-audience output
#
# Usage: ./due-diligence-swarm.sh <repo_path> [agents] [iterations]
# Example: ./due-diligence-swarm.sh ~/code/target-project 7 5

set -euo pipefail

REPO_PATH="${1:-}"
AGENTS="${2:-7}"
ITER="${3:-5}"

if [[ -z "$REPO_PATH" || ! -d "$REPO_PATH" ]]; then
    echo "Usage: $0 <repo_path> [agents] [iterations]"
    exit 1
fi

PROJECT_NAME=$(basename "$REPO_PATH")
APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_SCRIPT="${AGENT_SCRIPT:-$(dirname "$0")/research-agent.sh}"
OUTDIR="$HOME/due-diligence/$(date +%Y%m%d_%H%M%S)"
DIMENSIONSFILE="$OUTDIR/dimensions.txt"
MANIFEST="$OUTDIR/manifest.txt"
REPORT="$OUTDIR/technical_dd.md"
EXEC_SUMMARY="$OUTDIR/executive_summary.md"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Project    : $PROJECT_NAME"
echo "▶ Path       : $REPO_PATH"
echo "▶ Agents     : $AGENTS"
echo "▶ Iter/agent : $ITER"
echo "▶ Output     : $OUTDIR"
echo ""

espeak-ng "Starting technical due diligence on ${PROJECT_NAME}" 2>/dev/null || true

# ── Build project manifest ────────────────────────────────────────────────────
echo "── Building project manifest..."

{
    echo "=== PROJECT: $PROJECT_NAME ==="
    echo "=== PATH: $REPO_PATH ==="
    echo ""

    echo "=== DIRECTORY STRUCTURE ==="
    find "$REPO_PATH" -maxdepth 3 \
        ! -path "*/.git/*" ! -path "*/node_modules/*" \
        ! -path "*/__pycache__/*" ! -path "*/.venv/*" ! -path "*/venv/*" \
        | sort | head -120
    echo ""

    echo "=== FILE COUNTS BY EXTENSION ==="
    find "$REPO_PATH" -type f ! -path "*/.git/*" ! -path "*/node_modules/*" \
        | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -30
    echo ""

    echo "=== ROOT FILES ==="
    ls -la "$REPO_PATH"
    echo ""

    if [[ -f "$REPO_PATH/README.md" ]]; then
        echo "=== README ==="
        cat "$REPO_PATH/README.md"
        echo ""
    fi

    for MANIFEST_FILE in \
        "$REPO_PATH/pyproject.toml" \
        "$REPO_PATH/setup.py" \
        "$REPO_PATH/requirements.txt" \
        "$REPO_PATH/package.json" \
        "$REPO_PATH/go.mod" \
        "$REPO_PATH/Cargo.toml" \
        "$REPO_PATH/Dockerfile" \
        "$REPO_PATH/docker-compose.yml" \
        "$REPO_PATH/.github/workflows"
    do
        if [[ -f "$MANIFEST_FILE" ]]; then
            echo "=== $(basename "$MANIFEST_FILE") ==="
            cat "$MANIFEST_FILE"
            echo ""
        elif [[ -d "$MANIFEST_FILE" ]]; then
            echo "=== CI/CD WORKFLOWS ==="
            find "$MANIFEST_FILE" -name "*.yml" -exec cat {} \;
            echo ""
        fi
    done

    if git -C "$REPO_PATH" log --oneline -20 2>/dev/null; then
        echo ""
        echo "=== GIT LOG (last 20) ==="
        git -C "$REPO_PATH" log --oneline -20
        echo ""
        echo "=== CONTRIBUTORS ==="
        git -C "$REPO_PATH" shortlog -sn --all | head -20
        echo ""
        echo "=== COMMIT FREQUENCY ==="
        git -C "$REPO_PATH" log --format="%ad" --date=format:"%Y-%m" | \
            sort | uniq -c | tail -12
    fi

} > "$MANIFEST"

echo "   ✓ manifest built ($(wc -l < "$MANIFEST") lines)"

# ── Define DD dimensions ─────────────────────────────────────────────────────
echo ""
echo "── Defining DD dimensions..."

apex "You are a technical due diligence analyst assessing a software project for
an investor, acquirer, or technical board.

Project name: ${PROJECT_NAME}

Read the project manifest using read_file from ${MANIFEST}

Based on what you find in the manifest, decompose technical DD into exactly ${AGENTS}
orthogonal assessment dimensions. Choose the most relevant from:

- Architecture & design quality (patterns, coupling, modularity, scalability ceiling)
- Security posture (auth, input validation, secrets, dependency vulnerabilities)
- Code quality & maintainability (complexity, duplication, naming, style consistency)
- Test coverage & quality assurance (test types, coverage, CI discipline)
- Dependency health (freshness, licence risk, abandonment risk, supply chain)
- Scalability & performance (bottlenecks, caching, query patterns, concurrency model)
- Operational readiness (logging, observability, deployment, rollback, DR)
- Documentation completeness (API docs, onboarding, architecture decision records)
- Technical debt register (shortcuts, TODOs, known issues, migration burden)

Output exactly ${AGENTS} lines — one dimension per line — tailored to what you found.
No numbering, no bullets.
Write to ${DIMENSIONSFILE} using write_file"

[[ ! -f "$DIMENSIONSFILE" ]] && echo "✗ Dimension generation failed" && exit 1

echo "── DD dimensions:"
cat -n "$DIMENSIONSFILE"
echo ""

# ── Launch parallel agents ────────────────────────────────────────────────────
echo "── Launching ${AGENTS} agents in parallel..."

PIDS=()
i=0
while IFS= read -r dimension; do
    [[ -z "$dimension" ]] && continue
    AGENT_OUT="$OUTDIR/agent_${i}"
    mkdir -p "$AGENT_OUT"

    # Copy manifest to agent dir for file-based access
    cp "$MANIFEST" "$AGENT_OUT/manifest.txt"

    AUGMENTED_GOAL="Technical due diligence on project: ${PROJECT_NAME}

Your dimension: ${dimension}

Project manifest is available at ${AGENT_OUT}/manifest.txt
Read it using read_file before beginning analysis.

Produce a rigorous assessment of this dimension:
1. Current state — what does the project actually do in this area?
2. Strengths — what is done well?
3. Risks — what are the specific, concrete risks?
4. Risk severity — Critical / High / Medium / Low with justification
5. Evidence — cite specific files, patterns, or metrics from the manifest
6. Recommendations — specific remediations with effort estimates

Be specific to this project. Generic observations without evidence are not useful."

    (
        export OUTDIR_OVERRIDE="$AGENT_OUT"
        bash "$AGENT_SCRIPT" "$AUGMENTED_GOAL" "$ITER" 2>&1 | \
            sed "s/^/  [dd_${i}] /"
    ) &

    PIDS+=($!)
    echo "   agent_${i} (pid ${PIDS[-1]}): ${dimension:0:60}..."
    i=$((i+1))
done < "$DIMENSIONSFILE"

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

DD_DATE=$(date +"%B %d, %Y")

# ── Full technical report ─────────────────────────────────────────────────────
echo ""
echo "── Synthesising technical DD report..."

apex "You are a senior technical due diligence analyst at a technology advisory firm.
Project: ${PROJECT_NAME}
Date: ${DD_DATE}

Read the combined agent assessments using read_file from ${COMBINED}
Read the project manifest using read_file from ${MANIFEST}

Produce a full technical due diligence report in Markdown:

# Technical Due Diligence: ${PROJECT_NAME}
**Date:** ${DD_DATE}
**Prepared by:** Axiom LLC
**Scope:** Full technical assessment across ${AGENTS} dimensions

## Overall Assessment
**Technical Health Score:** X / 10
**Risk Rating:** (Low / Medium / High / Critical)
**Acquisition/Investment Readiness:** (Ready / Conditional / Not Recommended)

(3–5 sentence narrative of overall technical quality and trajectory)

## Risk Register
| ID | Dimension | Risk | Severity | Likelihood | Remediation Effort |
|----|-----------|------|----------|------------|-------------------|

## Dimension Scores
| Dimension | Score (1–10) | Key Finding |
|-----------|-------------|-------------|

## Detailed Findings
(one subsection per dimension — current state, evidence, risks, recommendations)

## Critical Blockers
(anything that must be resolved before investment or acquisition closes)

## Technical Debt Estimate
(rough effort to bring codebase to production-grade across all dimensions)

## Strengths Worth Preserving
(what is genuinely good — do not discard these in remediation)

## 90-Day Remediation Plan
(what a new technical owner should prioritise in the first 90 days)

---
*Assessment produced by Axiom LLC autonomous due diligence swarm.
Human expert review recommended for Critical and High severity findings.*

Rules:
- All findings grounded in manifest evidence — no speculation
- Scores justified by specific observations
- Resolve agent conflicts — note genuine disagreements

Write to ${REPORT} using write_file"

# ── Executive summary ─────────────────────────────────────────────────────────
echo ""
echo "── Writing executive summary..."

apex "Read the full technical DD report using read_file from ${REPORT}

Write a one-page executive summary for a non-technical audience (investors, board, legal):

# Executive Summary — Technical Due Diligence: ${PROJECT_NAME}
**Date:** ${DD_DATE} | **Prepared by:** Axiom LLC

## Verdict
(2 sentences: is this a technically sound investment, and why)

## What We Assessed
(bullet list of dimensions covered)

## Key Strengths
(3 bullets — specific, not generic)

## Key Risks
(3 bullets — business impact framing, not technical jargon)

## Required Actions Before Close
(bulleted list of any blockers with rough cost/time to resolve)

## Recommendation
(one sentence)

Translate technical findings into business risk language throughout.
Write to ${EXEC_SUMMARY} using write_file"

echo ""
echo "✓ Due diligence complete"
echo "  Dimensions    : $AGENTS"
echo "  Agent dirs    : $OUTDIR/agent_*"
echo "  Full report   : $REPORT"
echo "  Exec summary  : $EXEC_SUMMARY"

espeak-ng "Due diligence complete for ${PROJECT_NAME}. Full report and executive summary written." 2>/dev/null || true
