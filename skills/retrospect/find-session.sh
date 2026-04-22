#!/usr/bin/env bash
# find-session.sh — locate the current Claude Code session's JSONL transcript.
#
# Usage: find-session.sh [cwd]
# Prints the absolute path on stdout, or nothing (exit 1) if not found.
# Diagnostic messages go to stderr.

set -euo pipefail

cwd="${1:-$PWD}"
# Claude Code encodes a cwd into a project dir by replacing / with -.
encoded="${cwd//\//-}"

candidates=()
if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    candidates+=("$CLAUDE_CONFIG_DIR/projects/$encoded")
else
    for dir in "$HOME/.claude-personal" "$HOME/.claude-work" "$HOME/.claude"; do
        [[ -d "$dir/projects/$encoded" ]] && candidates+=("$dir/projects/$encoded")
    done
fi

if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "find-session: no project dir for cwd=$cwd (encoded=$encoded)" >&2
    exit 1
fi

# Most-recently-modified .jsonl across all candidate dirs wins.
latest=""
latest_mtime=0
for dir in "${candidates[@]}"; do
    while IFS= read -r -d '' f; do
        # stat -f %m on BSD (macOS); stat -c %Y on GNU. Try BSD first.
        mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
        if (( mtime > latest_mtime )); then
            latest_mtime=$mtime
            latest="$f"
        fi
    done < <(find "$dir" -maxdepth 1 -name '*.jsonl' -print0 2>/dev/null)
done

if [[ -z "$latest" ]]; then
    echo "find-session: no .jsonl in ${candidates[*]}" >&2
    exit 1
fi

echo "$latest"
