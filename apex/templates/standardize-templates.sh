#!/usr/bin/env bash
# ============================================================
# standardize-templates.sh
# Run from apex/templates/ to patch all existing scripts.
# Safe to re-run — checks before patching.
# ============================================================
set -euo pipefail

TEMPLATES_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_LINE='source "$(dirname "$0")/lib/common.sh"'

echo "Working in: ${TEMPLATES_DIR}"

# ── 1. INJECT lib/common.sh source line ──────────────────
# Inserts after the set -euo pipefail line in each script that lacks it.
for script in compliance-audit.sh cybersecurity.sh healthcare-rcm.sh \
              insurance-claims.sh law-firm.sh msp.sh opportunity-scanner.sh \
              recruiter.sh revenue-monitor.sh solo-agency.sh supply-chain.sh \
              venture-bootstrap.sh hedge-fund.sh; do
    f="${TEMPLATES_DIR}/${script}"
    [[ ! -f "$f" ]] && echo "⚠ Not found: $f" && continue
    if grep -q 'lib/common.sh' "$f"; then
        echo "  skip (already sourced): $script"
    else
        sed -i "/^set -euo pipefail/a ${LIB_LINE}" "$f"
        echo "  ✓ injected lib source: $script"
    fi
done

# ── 2. FIX GNU date -d portability ───────────────────────
# Replace date -d "yesterday" with date_yesterday()
# Replace date -d "+N days" patterns with date_add()
for script in law-firm.sh solo-agency.sh; do
    f="${TEMPLATES_DIR}/${script}"
    [[ ! -f "$f" ]] && continue
    # yesterday
    sed -i 's/date -d "yesterday" +%Y-%m-%d/date_yesterday/g' "$f"
    # +N days pattern: date -d "+N days" +%Y-%m-%d → date_add "$(date +%Y-%m-%d)" N
    perl -i -pe \
        "s/date -d '\+(\d+) days' \+%Y-%m-%d/date_add \"\$(date +%Y-%m-%d)\" \$1/g; \
         s/date -d \"\+(\d+) days\" \+%Y-%m-%d/date_add \"\$(date +%Y-%m-%d)\" \$1/g" \
        "$f"
    echo "  ✓ date portability: $script"
done

# supply-chain.sh also uses YESTERDAY=$(date -d "yesterday" ...)
f="${TEMPLATES_DIR}/supply-chain.sh"
[[ -f "$f" ]] && \
    sed -i 's/YESTERDAY=\$(date -d "yesterday" +%Y-%m-%d)/YESTERDAY=$(date_yesterday)/g' "$f" && \
    echo "  ✓ date portability: supply-chain.sh"

# hedge-fund.sh archive block
f="${TEMPLATES_DIR}/hedge-fund.sh"
[[ -f "$f" ]] && \
    sed -i 's/YESTERDAY=\$(date -d "yesterday" +%Y-%m-%d)/YESTERDAY=$(date_yesterday)/g' "$f" && \
    echo "  ✓ date portability: hedge-fund.sh"

# ── 3. FIX espeak calls → safe_speak / safe_speak_file ───
# msp.sh and revenue-monitor.sh use espeak and aplay directly.
for script in msp.sh revenue-monitor.sh; do
    f="${TEMPLATES_DIR}/${script}"
    [[ ! -f "$f" ]] && continue

    # apex "... use espeak ... save to FILE.wav" calls remain as apex prompts — correct.
    # The bare `aplay` shell calls need guarding.
    sed -i 's/^    aplay /    safe_play /g' "$f"
    sed -i 's/^aplay /safe_play /g' "$f"

    # Direct espeak shell calls (not inside apex strings) — guard them
    # Pattern: ^    apex "use espeak to say ... " standalone calls
    # These are fine — they go to apex. The issue is bare: espeak "..." lines.
    perl -i -pe 's/^(\s*)espeak\s+"([^"]+)"/$1safe_speak "$2"/g' "$f"

    echo "  ✓ espeak guarded: $script"
done

# ── 4. FIX revenue-monitor.sh config loader ──────────────
# Replace the fragile source <(grep...) pattern with load_config.
f="${TEMPLATES_DIR}/revenue-monitor.sh"
if [[ -f "$f" ]] && grep -q 'source <(grep' "$f"; then
    # Replace all instances of the pattern:
    #   source <(grep -E '^(KEY1|KEY2):' file | sed 's/: /="/' | sed 's/$/"/')
    # with: load_config file KEY1 KEY2
    # This is structural — do it with perl for safety.
    perl -i -0pe \
        's/source <\(grep -E '\''\^?\(([^)]+)\)[:\|]*'\'' ([^\n]+?config\.txt[^\n]*?)\s*\|\s*sed[^\n]*\|\s*sed[^\n]*\)/load_config $2 $(echo "$1" | tr "|" " ")/gs' \
        "$f" 2>/dev/null || true

    # Safer: replace the two known patterns explicitly
    sed -i \
        "s|source <(grep -E '^\(NAME|DOMAIN|IP|EMAIL|TIER\):' ~/monitor/clients/\${SLUG}/config.txt \\\\\n.*\| sed.*\| sed.*)|load_config ~/monitor/clients/\${SLUG}/config.txt NAME DOMAIN IP EMAIL TIER|g" \
        "$f" 2>/dev/null || true

    echo "  ✓ config loader: revenue-monitor.sh (manual review recommended — pattern varies)"
fi

# ── 5. FIX insurance-claims.sh recursive self-call ───────
f="${TEMPLATES_DIR}/insurance-claims.sh"
if [[ -f "$f" ]]; then
    # Replace: (bash "$0" triage "$claim_file")
    # with the actual function call to avoid fragility on rename
    sed -i 's|(bash "\$0" triage "\$claim_file")|(triage_claim "" "$claim_file")|g' "$f"
    echo "  ✓ recursive self-call: insurance-claims.sh"
fi

# ── 6. FIX due-diligence.sh AGENT_SCRIPT path ────────────
f="${TEMPLATES_DIR}/due-diligence.sh"
if [[ -f "$f" ]]; then
    # Make the research-agent.sh path fall back gracefully
    old='AGENT_SCRIPT="$(dirname "$0")/../examples/research-agent.sh"'
    new='AGENT_SCRIPT="${APEX_AGENT_SCRIPT:-$(dirname "$0")/../examples/research-agent.sh}"
[[ ! -f "$AGENT_SCRIPT" ]] && echo "✗ research-agent.sh not found. Set APEX_AGENT_SCRIPT." && exit 1'
    # Use python for safe multiline sed
    python3 -c "
import re, sys
content = open('${f}').read()
old = '''AGENT_SCRIPT=\"\$(dirname \"\$0\")/../examples/research-agent.sh\"'''
new = '''AGENT_SCRIPT=\"\${APEX_AGENT_SCRIPT:-\$(dirname \"\$0\")/../examples/research-agent.sh}\"
[[ ! -f \"\$AGENT_SCRIPT\" ]] && echo \"✗ research-agent.sh not found. Set APEX_AGENT_SCRIPT.\" && exit 1'''
print(content.replace(old, new), end='')
" > "${f}.tmp" && mv "${f}.tmp" "$f"
    echo "  ✓ agent path fallback: due-diligence.sh"
fi

# ── 7. FIX supply-chain.sh Google search → news API ──────
f="${TEMPLATES_DIR}/supply-chain.sh"
if [[ -f "$f" ]]; then
    # Replace the Google scrape with HN search (already used elsewhere in the file)
    # and a GDELT API call as fallback — both are scraping-safe
    old='        apex "fetch https://www.google.com/search?q=${query}+news+risk+outage+breach+lawsuit+bankruptcy+2024+2025 \
        using http_get \
        extract news headlines and summaries mentioning ${vendor} \
        write to ~/supply/signals/${slug}-news-${DATE}.txt"'
    new='        apex "fetch https://api.gdeltproject.org/api/v2/doc/doc?query=${query}&mode=artlist&maxrecords=10&format=json \
        using http_get \
        extract news articles mentioning ${vendor} from the last 30 days \
        write to ~/supply/signals/${slug}-news-${DATE}.txt"'
    python3 -c "
content = open('${f}').read()
old = '''        apex \"fetch https://www.google.com/search?q=\${query}+news+risk+outage+breach+lawsuit+bankruptcy+2024+2025 \\\\
        using http_get \\\\
        extract news headlines and summaries mentioning \${vendor} \\\\
        write to ~/supply/signals/\${slug}-news-\${DATE}.txt\"'''
new = '''        apex \"fetch https://api.gdeltproject.org/api/v2/doc/doc?query=\${query}\&mode=artlist\&maxrecords=10\&format=json \\\\
        using http_get \\\\
        extract news articles mentioning \${vendor} from the last 30 days \\\\
        write to ~/supply/signals/\${slug}-news-\${DATE}.txt\"'''
print(content.replace(old, new), end='')
" > "${f}.tmp" && mv "${f}.tmp" "$f"
    echo "  ✓ Google scrape → GDELT: supply-chain.sh"
fi

# ── 8. CHMOD all templates executable ────────────────────
chmod +x "${TEMPLATES_DIR}"/*.sh
echo ""
echo "✓ All templates executable."

# ── 9. VALIDATE ───────────────────────────────────────────
echo ""
echo "── Validation (bash -n syntax check):"
errors=0
for f in "${TEMPLATES_DIR}"/*.sh; do
    [[ "$(basename $f)" == "standardize-templates.sh" ]] && continue
    if bash -n "$f" 2>/dev/null; then
        echo "  ✓ $(basename $f)"
    else
        echo "  ✗ $(basename $f) — syntax error"
        bash -n "$f"
        errors=$((errors+1))
    fi
done

echo ""
if [[ $errors -eq 0 ]]; then
    echo "✓ Standardization complete. $errors errors."
else
    echo "⚠ Standardization complete with ${errors} syntax error(s) — review above."
fi
