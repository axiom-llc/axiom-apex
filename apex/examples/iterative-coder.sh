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
