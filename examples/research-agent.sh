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

# ── Available search tools (no keys required) ─────────────────────────────────
# Wikipedia summary : https://en.wikipedia.org/api/rest_v1/page/summary/TOPIC
# Wikipedia search  : https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=TERM&format=json
# HackerNews        : https://hn.algolia.com/api/v1/search?query=TERM
# DDG instant answer: https://api.duckduckgo.com/?q=TERM&format=json
# Reddit            : https://www.reddit.com/r/all/search.json?q=TERM&sort=relevance

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

# ── Bootstrap: let agent define its own goal if none given ────────────────────
FREEFORM_TRIGGERS=("self.directed" "free" "whatever" "your choice" "as you see fit" "do your own" "anything" "")
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
$(cat "$STATE")

---
Decide your next action. You have full freedom to act as needed to achieve the goal.
Choose ONE of the following actions and output it as the FIRST LINE of your response,
followed by your content:

ACTION: SEARCH
[URL to fetch using one of these APIs — pick the most useful one for what you need]
  Wikipedia summary : https://en.wikipedia.org/api/rest_v1/page/summary/TOPIC
  Wikipedia search  : https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=TERM&format=json
  HackerNews        : https://hn.algolia.com/api/v1/search?query=TERM
  DDG               : https://api.duckduckgo.com/?q=TERM&format=json
  Reddit            : https://www.reddit.com/r/all/search.json?q=TERM&sort=relevance
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
$(cat "$STATE")

Raw API response:
$(cat "$FETCH")

Extract only what is genuinely useful toward the goal.
Ignore metadata, formatting artifacts, boilerplate.
Pull out: key facts, definitions, mechanisms, names, dates, useful leads.
Note sub-topics worth investigating further.
100–200 words max, dense and specific.

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
$(cat "$STATE")

Your action was THINK. Write your reasoning here:
- Synthesise what you know so far
- Identify contradictions or gaps
- Decide what still needs to be found
- Note any conclusions you can draw now
150–250 words. Write to ${THOUGHT} using write_file"

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
$(cat "$STATE")

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
