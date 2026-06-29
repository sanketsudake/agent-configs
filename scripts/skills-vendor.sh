#!/usr/bin/env bash
#
# skills-vendor.sh — discover/fetch skills with the vercel-labs `skills` CLI
# (the skills.sh ecosystem), then vendor them into this repo's skills/ tree
# via resource-manager.sh so they keep a .source.json sidecar and stay
# manageable with the existing skills-list / skills-update / skills-delete
# targets and the Makefile symlinks.
#
# We use the `skills` CLI only as a *resolver + fetcher*: it knows skills.sh,
# resolves odd repo layouts, and records each skill's origin in a project
# skills-lock.json. We translate that lock into our own provenance model
# rather than letting the CLI install per-agent — that keeps the two custom
# Claude profiles (CLAUDE_CONFIG_DIR) and the claude/agents/ subagents, which
# the CLI does not handle, working exactly as before.
#
# Usage:
#   skills-vendor.sh --source <owner/repo[@skill] | url> [--skill "a b c" | --all] [--ref REF] [--category CAT] [--force]
#
# Network: the CLI and git both hit GitHub. Export GITHUB_TOKEN (or have `gh`
# logged in) to avoid anonymous rate limits.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_MANAGER="$SCRIPT_DIR/resource-manager.sh"

err()  { printf 'error: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }
info() { printf '%s\n' "$*" >&2; }

command -v jq  >/dev/null || die "jq is required"
command -v npx >/dev/null || die "npx (Node.js) is required to run the skills CLI"
[[ -x "$RESOURCE_MANAGER" ]] || die "resource-manager.sh not found at $RESOURCE_MANAGER"

source="" skills_arg="" all=0 ref="" category="" force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)   source="$2"; shift 2 ;;
    --skill)    skills_arg="$2"; shift 2 ;;
    --all)      all=1; shift ;;
    --ref)      ref="$2"; shift 2 ;;
    --category) category="$2"; shift 2 ;;
    --force)    force=1; shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done
[[ -n "$source" ]] || die "--source is required (e.g. owner/repo, owner/repo@skill, or a git URL)"

# Accept the `owner/repo@skill` shorthand that `skills find` prints: peel the
# @skill suffix into a selected skill so it can be pasted verbatim. Leave URLs
# (https://…, git@host:…) untouched.
if [[ "$source" != *"://"* && "$source" != git@* && "$source" == *@* ]]; then
  skills_arg="${skills_arg:+$skills_arg }${source##*@}"
  source="${source%@*}"
fi

# Stage the CLI's fetch in a throwaway project so its per-agent install and
# lockfile never touch the repo. --copy gives real files (not symlinks into
# the CLI cache); -a claude-code keeps it from prompting for an agent.
staging="$(mktemp -d)"
cleanup() { rm -rf "$staging"; }
trap cleanup EXIT

add_args=(add "$source" --copy -a claude-code -y)
if [[ "$all" -eq 1 ]]; then
  add_args+=(--skill '*')
elif [[ -n "$skills_arg" ]]; then
  # space- or comma-separated -> repeated --skill values
  read -r -a names <<<"${skills_arg//,/ }"
  for n in "${names[@]}"; do add_args+=(--skill "$n"); done
fi

info "==> resolving + fetching via skills CLI: $source"
( cd "$staging" && npx -y skills@latest "${add_args[@]}" ) \
  || die "skills CLI failed to fetch from $source"

lock="$staging/skills-lock.json"
[[ -f "$lock" ]] || die "skills CLI wrote no skills-lock.json (nothing fetched?)"

# Translate each lock entry into a resource-manager fetch so the vendored skill
# gets our standard .source.json. lock schema (v1):
#   skills.<name> = { source, sourceType, skillPath: "<subpath>/SKILL.md", ... }
# Read into an array with a while-loop (mapfile is bash 4+; macOS ships 3.2).
entries=()
while IFS= read -r line; do
  [[ -n "$line" ]] && entries+=("$line")
done < <(jq -r '.skills | to_entries[] | [.key, .value.source, .value.sourceType, .value.skillPath] | @tsv' "$lock")
[[ ${#entries[@]} -gt 0 ]] || die "skills-lock.json listed no skills"

vendored=0 failed=0
for entry in "${entries[@]}"; do
  IFS=$'\t' read -r name src stype skillpath <<<"$entry"
  if [[ "$stype" != "github" && "$src" != *"://"* && "$src" != git@* ]]; then
    err "$name: unsupported source '$src' (type $stype) — vendor it manually with skills-fetch; skipping"
    failed=$((failed + 1)); continue
  fi
  subpath="$(dirname "$skillpath")"   # skills/<name>/SKILL.md -> skills/<name>
  rm_args=(--kind skill fetch --repo "$src" --subpath "$subpath" --name "$name")
  [[ -n "$ref"      ]] && rm_args+=(--ref "$ref")
  [[ -n "$category" ]] && rm_args+=(--category "$category")
  [[ "$force" -eq 1 ]] && rm_args+=(--force)
  info "==> vendoring $name  ($src : $subpath)"
  if "$RESOURCE_MANAGER" "${rm_args[@]}"; then
    vendored=$((vendored + 1))
  else
    err "$name: resource-manager fetch failed (already vendored? use FORCE=1 to overwrite, or skills-update to refresh)"
    failed=$((failed + 1))
  fi
done

info "==> done: $vendored vendored, $failed skipped/failed"
[[ "$failed" -eq 0 ]]
