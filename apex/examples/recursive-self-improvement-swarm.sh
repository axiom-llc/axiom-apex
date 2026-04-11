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
