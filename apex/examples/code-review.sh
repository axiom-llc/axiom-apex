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
