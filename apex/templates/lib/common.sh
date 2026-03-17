#!/usr/bin/env bash
# ============================================================
# lib/common.sh — Shared utilities for apex templates
# Source this file at the top of any template:
#   source "$(dirname "$0")/lib/common.sh"
# ============================================================

# ── DATE PORTABILITY (GNU + BSD/macOS) ────────────────────
# Usage: date_add <date> <days>  →  YYYY-MM-DD
date_add() {
    local base="${1:-$(date +%Y-%m-%d)}"
    local days="$2"
    if date --version &>/dev/null 2>&1; then
        # GNU coreutils
        date -d "${base} +${days} days" +%Y-%m-%d
    else
        # BSD (macOS)
        date -j -v+${days}d -f "%Y-%m-%d" "${base}" +%Y-%m-%d
    fi
}

# Usage: date_yesterday  →  YYYY-MM-DD
date_yesterday() {
    if date --version &>/dev/null 2>&1; then
        date -d "yesterday" +%Y-%m-%d
    else
        date -j -v-1d +%Y-%m-%d
    fi
}

# ── ESPEAK GUARD ──────────────────────────────────────────
# Silently no-ops if espeak not available or no audio device.
# Usage: safe_speak "text to say"
safe_speak() {
    if command -v espeak &>/dev/null && [[ -n "${DISPLAY:-}" || -n "${APEX_AUDIO:-}" ]]; then
        espeak "$1" 2>/dev/null || true
    fi
}

# Usage: safe_speak_file "text" output.wav
safe_speak_file() {
    local text="$1"
    local outfile="$2"
    if command -v espeak &>/dev/null; then
        espeak "$text" -w "$outfile" 2>/dev/null || true
    fi
}

# Usage: safe_play file.wav
safe_play() {
    if command -v aplay &>/dev/null && [[ -f "$1" ]]; then
        aplay "$1" 2>/dev/null || true
    fi
}

# ── CONFIG LOADER ─────────────────────────────────────────
# Reads a flat key: value config file into variables.
# Usage: load_config ~/monitor/clients/slug/config.txt NAME DOMAIN TIER
# Sets variables $NAME, $DOMAIN, $TIER in calling scope.
load_config() {
    local config_file="$1"; shift
    local keys=("$@")
    [[ ! -f "$config_file" ]] && echo "✗ Config not found: $config_file" && return 1
    for key in "${keys[@]}"; do
        local val
        val=$(grep -E "^${key}:" "$config_file" | head -1 | sed 's/^[^:]*: *//')
        printf -v "$key" '%s' "$val"
    done
}

# ── WAIT WITH LOGGING ─────────────────────────────────────
# Usage: wait_pids "${PIDS[@]}"  — waits, reports failures
wait_pids() {
    local pids=("$@")
    local failed=0
    for pid in "${pids[@]}"; do
        wait "$pid" || { echo "   ⚠ pid $pid exited non-zero" >&2; failed=$((failed+1)); }
    done
    return $failed
}

# ── REQUIRE ───────────────────────────────────────────────
# Usage: require_file "$FILE" "usage string"
require_file() {
    [[ ! -f "$1" ]] && echo "✗ Not found: $1${2:+ — $2}" && exit 1
}

require_dir() {
    [[ ! -d "$1" ]] && echo "✗ Directory not found: $1${2:+ — $2}" && exit 1
}

require_cmd() {
    command -v "$1" &>/dev/null || { echo "✗ Required command not found: $1"; exit 1; }
}

# ── SLUG ──────────────────────────────────────────────────
# Usage: SLUG=$(slugify "My Company Name")
slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' /.:' '_' | tr -cd '[:alnum:]_-'
}

# ── LOG ───────────────────────────────────────────────────
# Usage: log ~/path/to/logfile "message"
log() {
    local logfile="$1"; shift
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $*" >> "$logfile"
}
