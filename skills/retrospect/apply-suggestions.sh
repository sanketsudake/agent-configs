#!/usr/bin/env bash
# apply-suggestions.sh — apply approved retrospect suggestions to CLAUDE.md
# and/or memory files.
#
# Usage: apply-suggestions.sh <scope> <payload.json>
#   scope : all | claude | memory
#   payload.json schema:
#     {
#       "claude_md": { "path": "...", "append": "..." },
#       "memory":    { "dir":  "...", "entries": [
#                        { "filename": "...", "content": "...", "index_line": "..." }
#                      ] }
#     }
#
# Safety:
#   - CLAUDE.md is backed up to CLAUDE.md.bak.<ts> before every write.
#   - Never overwrites existing content; only appends.
#   - Refuses to touch CLAUDE.md if it has >100 lines of uncommitted diff
#     AND is inside a git repo (protects mid-edit work). Override with
#     RETROSPECT_FORCE=1.
#   - Memory index (MEMORY.md) is appended to, not rewritten. Duplicate
#     index lines are skipped.

set -euo pipefail

scope="${1:-}"
payload="${2:-}"

if [[ -z "$scope" || -z "$payload" ]]; then
    echo "usage: apply-suggestions.sh <all|claude|memory> <payload.json>" >&2
    exit 2
fi
case "$scope" in
    all|claude|memory) ;;
    *) echo "invalid scope: $scope" >&2; exit 2 ;;
esac
[[ -f "$payload" ]] || { echo "payload not found: $payload" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq required" >&2; exit 2; }

ts=$(date +%Y%m%d%H%M%S)

apply_claude_md() {
    local path append backup diff_lines
    path=$(jq -r '.claude_md.path // empty' "$payload")
    append=$(jq -r '.claude_md.append // empty' "$payload")
    if [[ -z "$path" || -z "$append" ]]; then
        echo "claude: nothing to apply"
        return 0
    fi

    if [[ -f "$path" ]] && git -C "$(dirname "$path")" rev-parse --show-toplevel >/dev/null 2>&1; then
        diff_lines=$(git -C "$(dirname "$path")" diff --numstat -- "$path" 2>/dev/null | awk '{print $1+$2}')
        diff_lines=${diff_lines:-0}
        if (( diff_lines > 100 )) && [[ -z "${RETROSPECT_FORCE:-}" ]]; then
            echo "claude: refusing — $path has $diff_lines lines of uncommitted diff. Commit first, or re-run with RETROSPECT_FORCE=1." >&2
            return 1
        fi
    fi

    mkdir -p "$(dirname "$path")"
    if [[ -f "$path" ]]; then
        backup="$path.bak.$ts"
        cp "$path" "$backup"
        echo "claude: backup -> $backup"
        # Ensure a blank line before our append if the file doesn't already end with one.
        if [[ -n "$(tail -c1 "$path")" ]]; then
            printf '\n' >> "$path"
        fi
        printf '\n' >> "$path"
    else
        echo "claude: creating new $path"
    fi
    printf '%s\n' "$append" >> "$path"
    echo "claude: appended $(wc -l <<<"$append" | tr -d ' ') lines to $path"
}

apply_memory() {
    local dir entries count written skipped index filename content index_line
    dir=$(jq -r '.memory.dir // empty' "$payload")
    entries=$(jq -c '.memory.entries // [] | .[]' "$payload")
    if [[ -z "$dir" || -z "$entries" ]]; then
        echo "memory: nothing to apply"
        return 0
    fi

    mkdir -p "$dir"
    index="$dir/MEMORY.md"
    [[ -f "$index" ]] || : > "$index"

    written=0
    skipped=0
    while IFS= read -r entry; do
        filename=$(jq -r '.filename' <<<"$entry")
        content=$(jq -r '.content' <<<"$entry")
        index_line=$(jq -r '.index_line // empty' <<<"$entry")

        if [[ -e "$dir/$filename" ]]; then
            echo "memory: skip existing $filename"
            ((skipped+=1))
            continue
        fi
        printf '%s' "$content" > "$dir/$filename"
        ((written+=1))

        if [[ -n "$index_line" ]]; then
            if ! grep -Fqx -- "$index_line" "$index"; then
                # Ensure newline before appending.
                if [[ -s "$index" && -n "$(tail -c1 "$index")" ]]; then
                    printf '\n' >> "$index"
                fi
                printf '%s\n' "$index_line" >> "$index"
            fi
        fi
    done <<<"$entries"

    echo "memory: wrote $written, skipped $skipped — index $index"
}

case "$scope" in
    all)    apply_claude_md; apply_memory ;;
    claude) apply_claude_md ;;
    memory) apply_memory ;;
esac
