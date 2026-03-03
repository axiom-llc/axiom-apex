#!/usr/bin/env bash
# changelog-writer.sh — AI-driven changelog and release notes generator
# Reads git log, groups by type, infers semver bump, writes human-readable output
# Demonstrates: tool-assisted context ingestion, structured classification, doc generation
# Usage: ./changelog-writer.sh [repo_path] [since_ref]
# Example: ./changelog-writer.sh ~/myproject v1.2.0
#          ./changelog-writer.sh ~/myproject HEAD~30

set -euo pipefail

REPO_PATH="${1:-$PWD}"
SINCE_REF="${2:-}"

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="$HOME/changelog/$(date +%Y%m%d_%H%M%S)"
RAWLOG="$OUTDIR/git_log.txt"
DIFFSTAT="$OUTDIR/diffstat.txt"
CHANGELOG="$OUTDIR/CHANGELOG.md"
RELEASE_NOTES="$OUTDIR/RELEASE_NOTES.md"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

# ── Validate repo ─────────────────────────────────────────────────────────────
if [[ ! -d "$REPO_PATH/.git" ]]; then
    echo "✗ Not a git repository: $REPO_PATH"
    exit 1
fi

echo "▶ Repo   : $REPO_PATH"
echo "▶ Since  : ${SINCE_REF:-"(last 50 commits)"}"
echo "▶ Output : $OUTDIR"
echo ""

# ── Extract git data ──────────────────────────────────────────────────────────
echo "── Extracting git log..."

cd "$REPO_PATH"

if [[ -n "$SINCE_REF" ]]; then
    git log "${SINCE_REF}..HEAD" \
        --pretty=format:"COMMIT: %H%nAUTHOR: %an <%ae>%nDATE: %ad%nSUBJECT: %s%nBODY: %b%n---" \
        --date=short > "$RAWLOG"
else
    git log -50 \
        --pretty=format:"COMMIT: %H%nAUTHOR: %an <%ae>%nDATE: %ad%nSUBJECT: %s%nBODY: %b%n---" \
        --date=short > "$RAWLOG"
fi

COMMIT_COUNT=$(grep -c "^COMMIT:" "$RAWLOG" || echo 0)

if [[ "$COMMIT_COUNT" -eq 0 ]]; then
    echo "✗ No commits found in range"
    exit 1
fi

# ── Diffstat ──────────────────────────────────────────────────────────────────
if [[ -n "$SINCE_REF" ]]; then
    git diff --stat "${SINCE_REF}..HEAD" > "$DIFFSTAT" 2>/dev/null || true
else
    git diff --stat HEAD~"$COMMIT_COUNT"..HEAD > "$DIFFSTAT" 2>/dev/null || true
fi

CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")

echo "   ✓ $COMMIT_COUNT commits extracted"
echo "   ✓ Current version tag: $CURRENT_VERSION"

cd "$APEX_ROOT"

# ── Classification pass ───────────────────────────────────────────────────────
echo ""
echo "── Classifying commits..."

CLASSIFIED="$OUTDIR/classified.json"

apex "You are a release engineer analysing a git log to produce a structured changelog.

Read the git log using read_file from ${RAWLOG}

Classify every commit into one of these categories:
- feat       : new user-facing feature
- fix        : bug fix
- security   : security patch or hardening
- perf       : performance improvement
- breaking   : breaking change (API, interface, behaviour)
- refactor   : internal restructure, no behaviour change
- deps       : dependency update
- docs       : documentation only
- chore      : build, CI, tooling, release plumbing
- skip       : merge commits, version bumps, noise — omit these

For each non-skip commit output a JSON object with:
{
  \"hash\": \"short 7-char hash\",
  \"type\": \"category from above\",
  \"scope\": \"component or module affected, or null\",
  \"summary\": \"one tight sentence in past tense, imperative mood\",
  \"breaking\": true/false,
  \"author\": \"name only\"
}

Output a JSON array of these objects. No markdown fences. Valid JSON only.
Write to ${CLASSIFIED} using write_file"

[[ ! -f "$CLASSIFIED" ]] && echo "✗ Classification failed" && exit 1
echo "   ✓ classified"

# ── Semver inference ──────────────────────────────────────────────────────────
echo ""
echo "── Inferring semver bump..."

SEMVER_FILE="$OUTDIR/semver.txt"

apex "Read the classified commits from ${CLASSIFIED} using read_file.
Current version: ${CURRENT_VERSION}

Determine the correct semver bump:
- MAJOR if any commit has breaking: true
- MINOR if any feat commits exist (and no breaking)
- PATCH if only fix, security, perf, refactor, deps, docs, chore

Output exactly three lines:
BUMP: (major|minor|patch)
CURRENT: ${CURRENT_VERSION}
NEXT: (calculated next version string)

Write to ${SEMVER_FILE} using write_file"

if [[ -f "$SEMVER_FILE" ]]; then
    NEXT_VERSION=$(grep "^NEXT:" "$SEMVER_FILE" | awk '{print $2}')
    BUMP_TYPE=$(grep "^BUMP:" "$SEMVER_FILE" | awk '{print $2}')
    echo "   ✓ $CURRENT_VERSION → $NEXT_VERSION ($BUMP_TYPE bump)"
else
    NEXT_VERSION="UNKNOWN"
    BUMP_TYPE="unknown"
fi

# ── CHANGELOG.md ─────────────────────────────────────────────────────────────
echo ""
echo "── Writing CHANGELOG.md..."

RELEASE_DATE=$(date +%Y-%m-%d)

apex "You are writing a professional CHANGELOG.md entry.

Read the classified commits from ${CLASSIFIED} using read_file.

Write a changelog section for version ${NEXT_VERSION} (${RELEASE_DATE}).
Use Keep a Changelog format (https://keepachangelog.com):

## [${NEXT_VERSION}] — ${RELEASE_DATE}

Include only sections that have content. Section order:
### Breaking Changes   (breaking commits — red-flag these clearly)
### Added              (feat)
### Fixed              (fix)
### Security           (security)
### Performance        (perf)
### Changed            (refactor, deps)
### Documentation      (docs)

Rules:
- Each entry: bullet, past tense, imperative — e.g. 'Added OAuth2 token refresh endpoint'
- Include scope in brackets if present: '[auth] Added OAuth2...'
- Group related commits into single entries where appropriate
- Omit chore/skip entirely

Write to ${CHANGELOG} using write_file"

# ── Release notes ─────────────────────────────────────────────────────────────
echo ""
echo "── Writing release notes..."

apex "You are writing release notes for a public audience (developers and end users).

Read the CHANGELOG entry from ${CHANGELOG} using read_file.
Read the diffstat from ${DIFFSTAT} using read_file.

Write polished release notes for version ${NEXT_VERSION}:

# Release ${NEXT_VERSION}

## What's New
(2–3 sentence narrative highlight of the most impactful changes — no bullet points)

## Highlights
(3–5 bullet points: the changes users will actually care about)

## Breaking Changes
(if any — clear migration instructions, not just what changed but how to adapt)

## Installation / Upgrade
\`\`\`
pip install --upgrade <package>==\${NEXT_VERSION}
\`\`\`

## Stats
(files changed, insertions, deletions — from diffstat)

Tone: precise, confident, developer-facing. No marketing language.
Write to ${RELEASE_NOTES} using write_file"

echo ""
echo "✓ Done"
echo "  Version    : $CURRENT_VERSION → $NEXT_VERSION ($BUMP_TYPE)"
echo "  Commits    : $COMMIT_COUNT"
echo "  Changelog  : $CHANGELOG"
echo "  Release    : $RELEASE_NOTES"

espeak-ng "Changelog complete. Version ${NEXT_VERSION}, ${COMMIT_COUNT} commits, ${BUMP_TYPE} bump." 2>/dev/null || true
