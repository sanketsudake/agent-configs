#!/usr/bin/env bash
# find-sessions.sh — locate Claude Code session JSONL transcripts.
#
# Usage:
#   find-sessions.sh [--current] [cwd]   Print the current session's JSONL
#                                        (most-recently-modified for cwd). Default mode.
#   find-sessions.sh --since <N>[d]      List session JSONLs modified within the last N days,
#                                        across every project dir in the active profile,
#                                        newest first (one absolute path per line).
#
# Prints absolute path(s) on stdout; diagnostics on stderr. Exit 1 if none found.

set -euo pipefail

# mtime in epoch seconds — BSD (macOS) first, then GNU.
mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# Active profile config dir(s). Prefer the explicit one, else the known profiles.
config_dirs() {
    if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
        [[ -d "$CLAUDE_CONFIG_DIR/projects" ]] && printf '%s\n' "$CLAUDE_CONFIG_DIR"
    else
        for dir in "$HOME/.claude-personal" "$HOME/.claude-work" "$HOME/.claude"; do
            [[ -d "$dir/projects" ]] && printf '%s\n' "$dir"
        done
    fi
}

mode="--current"
arg=""
case "${1:-}" in
    --since)   mode="--since";   arg="${2:-}" ;;
    --current) mode="--current"; arg="${2:-}" ;;
    "")        mode="--current" ;;
    -*)        echo "find-sessions: unknown option $1" >&2; exit 2 ;;
    *)         mode="--current"; arg="$1" ;;
esac

if [[ "$mode" == "--current" ]]; then
    # Claude Code encodes a cwd into a project dir name by replacing / with -.
    cwd="${arg:-$PWD}"
    encoded="${cwd//\//-}"
    latest=""; latest_mtime=0
    while IFS= read -r cfg; do
        proj="$cfg/projects/$encoded"
        [[ -d "$proj" ]] || continue
        while IFS= read -r -d '' f; do
            m=$(mtime_of "$f")
            if (( m > latest_mtime )); then latest_mtime=$m; latest="$f"; fi
        done < <(find "$proj" -maxdepth 1 -name '*.jsonl' -print0 2>/dev/null)
    done < <(config_dirs)
    if [[ -z "$latest" ]]; then
        echo "find-sessions: no .jsonl for cwd=$cwd (encoded=$encoded)" >&2
        exit 1
    fi
    echo "$latest"
    exit 0
fi

# --since mode: list recent sessions across all projects, newest first.
days="${arg%d}"
if ! [[ "$days" =~ ^[0-9]+$ ]]; then
    echo "find-sessions: --since needs a day count, e.g. --since 7 or --since 7d" >&2
    exit 2
fi
cutoff=$(( $(date +%s) - days * 86400 ))

results=$(
    while IFS= read -r cfg; do
        while IFS= read -r -d '' f; do
            m=$(mtime_of "$f")
            (( m >= cutoff )) || continue
            printf '%s\t%s\n' "$m" "$f"
        done < <(find "$cfg/projects" -maxdepth 2 -name '*.jsonl' -print0 2>/dev/null)
    done < <(config_dirs) | sort -rn | cut -f2-
)

if [[ -z "$results" ]]; then
    echo "find-sessions: no .jsonl modified in the last $days days" >&2
    exit 1
fi
printf '%s\n' "$results"
