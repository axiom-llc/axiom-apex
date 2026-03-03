#!/usr/bin/env bash
# threat-model-swarm.sh — Parallel AI-driven security threat modelling swarm
# Axiom LLC — https://github.com/axiom-llc/apex
#
# Each agent analyses a distinct attack surface or threat category.
# Synthesises into a full STRIDE-aligned threat model document.
#
# Demonstrates: parallel security analysis, structured threat enumeration,
# STRIDE/DREAD classification, risk-ranked mitigation roadmap
#
# Usage: ./threat-model-swarm.sh "system description" [agents] [iterations]
# Example: ./threat-model-swarm.sh "SaaS API platform with JWT auth, PostgreSQL, Redis, S3" 6 5

set -euo pipefail

SYSTEM="${1:-}"
AGENTS="${2:-6}"
ITER="${3:-5}"

if [[ -z "$SYSTEM" ]]; then
    echo "Usage: $0 \"system description\" [agents] [iterations]"
    echo "Tip: be specific — list components, auth mechanisms, data stores, network topology"
    exit 1
fi

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_SCRIPT="${AGENT_SCRIPT:-$(dirname "$0")/research-agent.sh}"
OUTDIR="$HOME/threat-model/$(date +%Y%m%d_%H%M%S)"
SURFACESFILE="$OUTDIR/attack_surfaces.txt"
THREATMODEL="$OUTDIR/threat_model.md"
MITIGATIONS="$OUTDIR/mitigations.md"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ System     : $SYSTEM"
echo "▶ Agents     : $AGENTS"
echo "▶ Iter/agent : $ITER"
echo "▶ Output     : $OUTDIR"
echo ""

espeak-ng "Starting threat model swarm. Analysing ${AGENTS} attack surfaces." 2>/dev/null || true

# ── Decompose attack surfaces ─────────────────────────────────────────────────
echo "── Decomposing attack surfaces..."

apex "You are a principal security architect performing threat modelling on this system:
${SYSTEM}

Decompose the system into exactly ${AGENTS} distinct attack surfaces or threat categories
that can be independently and deeply analysed.

Draw from STRIDE categories and modern attack patterns:
- Spoofing: identity, authentication bypass, credential attacks
- Tampering: data integrity, injection, supply chain
- Repudiation: audit trail gaps, log manipulation
- Information Disclosure: data exfiltration, over-exposure, insecure storage
- Denial of Service: resource exhaustion, availability attacks
- Elevation of Privilege: authorisation bypass, IDOR, SSRF, privilege escalation
- Supply chain & dependency attacks
- Infrastructure & deployment surface (CI/CD, secrets, config)

Output exactly ${AGENTS} lines. One attack surface per line.
Each: a specific research goal — what threats to enumerate and analyse for this system.
No numbering, no bullets.
Write to ${SURFACESFILE} using write_file"

[[ ! -f "$SURFACESFILE" ]] && echo "✗ Attack surface decomposition failed" && exit 1

echo "── Attack surfaces:"
cat -n "$SURFACESFILE"
echo ""

# ── Launch parallel agents ────────────────────────────────────────────────────
echo "── Launching ${AGENTS} agents in parallel..."

PIDS=()
i=0
while IFS= read -r surface; do
    [[ -z "$surface" ]] && continue
    AGENT_OUT="$OUTDIR/agent_${i}"
    mkdir -p "$AGENT_OUT"

    AUGMENTED_GOAL="System under analysis: ${SYSTEM}

Security research goal: ${surface}

For this attack surface, enumerate and analyse:
1. Specific threats relevant to this system
2. Attack vectors and prerequisites for each
3. Real-world CVEs or incidents involving similar systems
4. Detection methods — what signals indicate exploitation
5. Mitigations — ranked by effectiveness and implementation cost

Use HackerNews and Reddit to find real incidents, CVEs, and practitioner discussion.
Be specific to the system described — generic advice is not useful."

    (
        export OUTDIR_OVERRIDE="$AGENT_OUT"
        bash "$AGENT_SCRIPT" "$AUGMENTED_GOAL" "$ITER" 2>&1 | \
            sed "s/^/  [threat_${i}] /"
    ) &

    PIDS+=($!)
    echo "   agent_${i} (pid ${PIDS[-1]}): ${surface:0:60}..."
    i=$((i+1))
done < "$SURFACESFILE"

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
        echo "=== SURFACE ${j} ===" >> "$COMBINED"
        cat "$AGENT_REPORT" >> "$COMBINED"
        echo "" >> "$COMBINED"
        echo "   ✓ agent_${j} collected"
    else
        echo "   ⚠ agent_${j} no report"
    fi
done

# ── Threat model synthesis ────────────────────────────────────────────────────
echo ""
echo "── Synthesising threat model..."

MODEL_DATE=$(date +"%B %d, %Y")

apex "You are a principal security architect synthesising a formal threat model.
System: ${SYSTEM}
Date: ${MODEL_DATE}

Read the combined agent findings using read_file from ${COMBINED}

Produce a complete STRIDE-aligned threat model in Markdown:

# Threat Model: ${SYSTEM}
**Date:** ${MODEL_DATE}
**Prepared by:** Axiom LLC
**Methodology:** STRIDE + DREAD scoring

## System Overview & Trust Boundaries
(brief description, components, data flows, trust zones inferred from the system description)

## Threat Register
(comprehensive table of all identified threats)

| ID | Category | Component | Threat | Attack Vector | DREAD Score (1–10) | Status |
|----|----------|-----------|--------|---------------|-------------------|--------|

DREAD = Damage + Reproducibility + Exploitability + Affected users + Discoverability (avg)
Status: Open / Mitigated / Accepted

## Critical Threats (DREAD ≥ 7)
(expanded detail on highest-risk threats — mechanism, prerequisites, real-world precedent)

## Attack Chains
(2–3 multi-step attack scenarios that chain individual threats into realistic kill chains)

## Security Controls Inventory
(what protections are implied by the system design, and their coverage gaps)

## Risk Heatmap
(markdown table: Likelihood vs Impact grid with threat IDs placed in cells)

Rules:
- Threat IDs: T-001, T-002, etc.
- Specific to this system — no generic CWE boilerplate without system context
- Reference real CVEs or incidents from agent research where applicable
- Resolve conflicts between agents — use highest-severity assessment

Write to ${THREATMODEL} using write_file"

# ── Mitigation roadmap ────────────────────────────────────────────────────────
echo ""
echo "── Writing mitigation roadmap..."

apex "Read the threat model from ${THREATMODEL} using read_file.

Produce a prioritised mitigation roadmap in Markdown:

# Mitigation Roadmap: ${SYSTEM}

## Immediate Actions (P0 — implement before next deployment)
(critical threats only — specific remediation steps, not general guidance)

## Short-term (P1 — within current sprint)
(high DREAD threats — what to build, configure, or patch)

## Medium-term (P2 — within quarter)
(architectural improvements, monitoring, detection engineering)

## Long-term (P3 — strategic hardening)
(zero-trust architecture moves, security programme investments)

## Security Testing Checklist
(specific test cases derived from the threat register — what a pentester should verify)

For each item:
- Threat ID(s) addressed
- Specific action (not 'improve logging' — 'add structured audit log for all
  authentication events with IP, user agent, and outcome')
- Effort estimate: (hours/days/weeks)
- Owner: (role, not individual)

Write to ${MITIGATIONS} using write_file"

THREAT_COUNT=$(grep -c "^| T-" "$THREATMODEL" 2>/dev/null || echo "unknown")

echo ""
echo "✓ Swarm complete"
echo "  Threats identified : $THREAT_COUNT"
echo "  Agent dirs         : $OUTDIR/agent_*"
echo "  Threat model       : $THREATMODEL"
echo "  Mitigations        : $MITIGATIONS"

espeak-ng "Threat model complete. ${THREAT_COUNT} threats identified. Mitigation roadmap written." 2>/dev/null || true
