#!/usr/bin/env bash
#
# resource-manager.sh — fetch, list, update, and delete vendored resources
# (skills or agents) from arbitrary git repos, tracking each resource's source.
#
# A "skill" is a directory containing SKILL.md, vendored under skills/.
# An "agent" is a single .md file, vendored under claude/agents/.
#
# Each managed resource carries a sidecar recording where it came from, plus an
# optional category used to group `list` output:
#   remote: {"repo","subpath","ref","commit","fetched_at"[,"category"]}
#   local:  {"repo": null, "note": "..."[, "category"]}
# A resource with no sidecar is "unmanaged".
#   skill sidecar: skills/<name>/.source.json        (inside the dir)
#   agent sidecar: claude/agents/<name>.source.json  (sibling of the .md)
#
# Usage:
#   resource-manager.sh --kind {skill|agent} fetch  (--url URL | --repo REPO --subpath SUBPATH) [--ref REF] [--name NAME] [--category CAT] [--force]
#   resource-manager.sh --kind {skill|agent} list
#   resource-manager.sh --kind {skill|agent} update (--name NAME | --all)
#   resource-manager.sh --kind {skill|agent} delete --name NAME [--yes]
#   resource-manager.sh --kind {skill|agent} category --name NAME --category CAT
#   resource-manager.sh --kind skill catalog [--check]
#   resource-manager.sh --kind {skill|agent} doctor
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

err()  { printf 'error: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }
info() { printf '%s\n' "$*" >&2; }
rel()  { printf '%s' "${1#"$REPO_ROOT"/}"; }

command -v git >/dev/null || die "git is required"
command -v jq  >/dev/null || die "jq is required"

# Temp dirs are tracked globally and cleaned once on exit. A per-function
# RETURN trap would be wrong here: bash traps are global, so it would re-fire
# for callers after the local $tmp went out of scope.
TMPDIRS=()
cleanup_tmpdirs() { local d; for d in "${TMPDIRS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; return 0; }
trap cleanup_tmpdirs EXIT
# Create a tracked temp dir, returning its path in $MKTMP_DIR. The path is
# returned via a global rather than command substitution so the registry
# append runs in this shell, not a subshell (where it would be lost).
mktmp() { MKTMP_DIR="$(mktemp -d)"; TMPDIRS+=("$MKTMP_DIR"); }

# --- kind configuration ----------------------------------------------------
# KIND and RESOURCE_ROOT are set by the --kind selector before any command.

KIND=""
RESOURCE_ROOT=""

configure_kind() {
  case "$KIND" in
    skill) RESOURCE_ROOT="$REPO_ROOT/skills" ;;
    agent) RESOURCE_ROOT="$REPO_ROOT/claude/agents" ;;
    *) die "missing or unknown --kind '$KIND' (expected skill|agent)" ;;
  esac
}

# Primary artifact path for a resource (a dir for skills, a .md file for agents).
artifact_path() {
  case "$KIND" in
    skill) printf '%s/%s' "$RESOURCE_ROOT" "$1" ;;
    agent) printf '%s/%s.md' "$RESOURCE_ROOT" "$1" ;;
  esac
}

# Sidecar path: inside the dir for skills, sibling of the .md for agents.
sidecar_path() {
  case "$KIND" in
    skill) printf '%s/%s/.source.json' "$RESOURCE_ROOT" "$1" ;;
    agent) printf '%s/%s.source.json' "$RESOURCE_ROOT" "$1" ;;
  esac
}

# Default resource name from a subpath.
default_name() {
  case "$KIND" in
    skill) basename "$1" ;;
    agent) basename "$1" .md ;;
  esac
}

# Sparse-checkout path for a subpath: the dir itself for skills, the parent dir
# for agents (since the agent subpath is a file).
sparse_set_path() {
  case "$KIND" in
    skill) printf '%s' "$1" ;;
    agent) dirname "$1" ;;
  esac
}

# Validate that <clone>/<subpath> is a well-formed resource of this kind.
validate_artifact() {
  local src="$1" subpath="$2"
  case "$KIND" in
    skill) [[ -f "$src/SKILL.md" ]] || return 1 ;;
    agent) [[ "$subpath" == *.md && -f "$src" ]] || return 1 ;;
  esac
}

# Copy <clone>/<subpath> into the managed tree at <dest>.
copy_artifact() {
  local src="$1" dest="$2"
  mkdir -p "$RESOURCE_ROOT"
  case "$KIND" in
    skill) rm -rf "$dest"; cp -R "$src" "$dest" ;;
    agent) cp "$src" "$dest" ;;
  esac
}

# Emit "name<TAB>sidecar_path" for each managed resource of this kind.
iter_resources() {
  case "$KIND" in
    skill)
      local dir name
      for dir in "$RESOURCE_ROOT"/*/; do
        [[ -d "$dir" ]] || continue
        name="$(basename "$dir")"
        printf '%s\t%s\n' "$name" "$dir.source.json"
      done
      ;;
    agent)
      local f name
      for f in "$RESOURCE_ROOT"/*.md; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f" .md)"
        printf '%s\t%s\n' "$name" "$RESOURCE_ROOT/$name.source.json"
      done
      ;;
  esac
}

# --- shared helpers --------------------------------------------------------

# Normalize a repo reference into a clone URL.
#   owner/name            -> https://github.com/owner/name
#   https://..., git@...  -> passed through unchanged
normalize_repo() {
  local repo="$1"
  if [[ "$repo" == *"://"* || "$repo" == git@* ]]; then
    printf '%s' "$repo"
  elif [[ "$repo" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    printf 'https://github.com/%s' "$repo"
  else
    die "cannot interpret repo '$repo' (expected owner/name or a clone URL)"
  fi
}

# Parse a GitHub tree/blob URL into repo|ref|subpath, tab-separated.
#   https://github.com/owner/name/tree/<ref>/<subpath...>
parse_github_url() {
  local url="$1"
  local re='^https?://github\.com/([^/]+)/([^/]+)/(tree|blob)/([^/]+)/(.+)$'
  [[ "$url" =~ $re ]] || die "not a github tree/blob URL: $url"
  printf 'https://github.com/%s/%s\t%s\t%s' \
    "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}"
}

# Shallow sparse-clone <repo> at <ref> (empty ref = default branch) into <dest>,
# narrowed to <set_path> (empty or "." = top-level files only).
sparse_clone() {
  local repo="$1" ref="$2" set_path="$3" dest="$4"
  local args=(--depth=1 --filter=blob:none --sparse)
  [[ -n "$ref" ]] && args+=(--branch "$ref")
  git clone "${args[@]}" "$repo" "$dest" >/dev/null 2>&1 \
    || die "clone failed: $repo${ref:+ (ref $ref)}"
  if [[ -n "$set_path" && "$set_path" != "." ]]; then
    git -C "$dest" sparse-checkout set "$set_path" >/dev/null 2>&1 \
      || die "sparse-checkout failed for: $set_path"
  fi
}

# Write a remote sidecar for <name>. A non-empty <category> is recorded; empty
# is omitted (keeps uncategorized sidecars clean).
write_sidecar() {
  local name="$1" repo="$2" subpath="$3" ref="$4" commit="$5" category="${6:-}"
  local fetched_at; fetched_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n \
    --arg repo "$repo" --arg subpath "$subpath" --arg ref "$ref" \
    --arg commit "$commit" --arg fetched_at "$fetched_at" --arg category "$category" \
    '{repo:$repo, subpath:$subpath, ref:$ref, commit:$commit, fetched_at:$fetched_at}
     + (if $category == "" then {} else {category:$category} end)' \
    > "$(sidecar_path "$name")"
}

# --- subcommands -----------------------------------------------------------

cmd_fetch() {
  local url="" repo="" subpath="" ref="" name="" category="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --url)      url="$2"; shift 2 ;;
      --repo)     repo="$2"; shift 2 ;;
      --subpath)  subpath="$2"; shift 2 ;;
      --ref)      ref="$2"; shift 2 ;;
      --name)     name="$2"; shift 2 ;;
      --category) category="$2"; shift 2 ;;
      --force)    force=1; shift ;;
      *) die "fetch: unknown argument '$1'" ;;
    esac
  done

  # A URL supplies defaults; explicit flags override.
  if [[ -n "$url" ]]; then
    local parsed; parsed="$(parse_github_url "$url")"
    IFS=$'\t' read -r u_repo u_ref u_subpath <<<"$parsed"
    [[ -z "$repo"    ]] && repo="$u_repo"
    [[ -z "$ref"     ]] && ref="$u_ref"
    [[ -z "$subpath" ]] && subpath="$u_subpath"
  fi

  [[ -n "$repo"    ]] || die "fetch: --repo or --url is required"
  [[ -n "$subpath" ]] || die "fetch: --subpath or --url is required"
  subpath="${subpath%/}"
  [[ -n "$name" ]] || name="$(default_name "$subpath")"

  local dest; dest="$(artifact_path "$name")"
  if [[ -e "$dest" && "$force" -ne 1 ]]; then
    die "$(rel "$dest") already exists (use FORCE=1 to overwrite, or ${KIND}s-update to refresh)"
  fi

  repo="$(normalize_repo "$repo")"
  local tmp; mktmp; tmp="$MKTMP_DIR"

  info "fetching $KIND $name from $repo${ref:+ @ $ref} ($subpath)"
  sparse_clone "$repo" "$ref" "$(sparse_set_path "$subpath")" "$tmp/repo"

  local commit; commit="$(git -C "$tmp/repo" rev-parse HEAD)"
  [[ -n "$ref" ]] || ref="$(git -C "$tmp/repo" rev-parse --abbrev-ref HEAD)"
  validate_artifact "$tmp/repo/$subpath" "$subpath" \
    || die "$subpath in $repo is not a valid $KIND"

  copy_artifact "$tmp/repo/$subpath" "$dest"
  write_sidecar "$name" "$repo" "$subpath" "$ref" "$commit" "$category"
  info "fetched $(rel "$dest") @ ${commit:0:7}${category:+ [$category]}"
}

# List resources grouped by category. Each row's category comes from its
# sidecar's `.category` (uncategorized if absent); rows are bucketed under a
# `<category> (<count>)` header with an aligned table.
cmd_list() {
  local data="" name sidecar repo subpath ref commit fetched category status
  while IFS=$'\t' read -r name sidecar; do
    [[ -n "$name" ]] || continue
    repo=-; subpath=-; ref=-; commit=-; fetched=-
    if [[ ! -f "$sidecar" ]]; then
      status=unmanaged; category=uncategorized
    else
      category="$(jq -r '.category // "uncategorized"' "$sidecar")"
      repo="$(jq -r '.repo // empty' "$sidecar")"
      if [[ -z "$repo" ]]; then
        status=local; repo=-
      else
        status=remote
        subpath="$(jq -r '.subpath // "-"' "$sidecar")"
        ref="$(jq -r '.ref // "-"' "$sidecar")"
        commit="$(jq -r '.commit // "-"' "$sidecar")"; commit="${commit:0:7}"
        fetched="$(jq -r '.fetched_at // "-"' "$sidecar")"
      fi
    fi
    data+="$category"$'\t'"$name"$'\t'"$status"$'\t'"$repo"$'\t'"$subpath"$'\t'"$ref"$'\t'"$commit"$'\t'"$fetched"$'\n'
  done < <(iter_resources)

  [[ -n "$data" ]] || { info "no ${KIND}s found"; return 0; }

  local cat count
  while IFS= read -r cat; do
    [[ -n "$cat" ]] || continue
    count="$(printf '%s' "$data" | awk -F'\t' -v c="$cat" '$1==c' | grep -c .)"
    printf '\n%s (%s)\n' "$cat" "$count"
    { printf 'NAME\tSTATUS\tREPO\tSUBPATH\tREF\tCOMMIT\tFETCHED_AT\n'
      printf '%s' "$data" | awk -F'\t' -v c="$cat" '$1==c {print $2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8}'
    } | column -t -s $'\t'
  done < <(printf '%s' "$data" | cut -f1 | sort -u)
}

# Re-fetch one remote resource in place. Reports via stderr.
update_one() {
  local name="$1"
  local artifact sidecar
  artifact="$(artifact_path "$name")"
  sidecar="$(sidecar_path "$name")"
  [[ -e "$artifact" ]] || { err "$name: no such $KIND"; return 1; }
  if [[ ! -f "$sidecar" ]]; then
    info "$name: unmanaged (no .source.json), skipping"
    return 0
  fi
  local repo; repo="$(jq -r '.repo // empty' "$sidecar")"
  if [[ -z "$repo" ]]; then
    info "$name: local $KIND, nothing to update"
    return 0
  fi
  local subpath ref old_commit category
  subpath="$(jq -r '.subpath' "$sidecar")"
  ref="$(jq -r '.ref' "$sidecar")"
  old_commit="$(jq -r '.commit' "$sidecar")"
  category="$(jq -r '.category // ""' "$sidecar")"   # preserve across re-fetch

  local tmp; mktmp; tmp="$MKTMP_DIR"
  sparse_clone "$repo" "$ref" "$(sparse_set_path "$subpath")" "$tmp/repo"
  local new_commit; new_commit="$(git -C "$tmp/repo" rev-parse HEAD)"

  if [[ "$new_commit" == "$old_commit" ]]; then
    info "$name: up to date (${old_commit:0:7})"
    return 0
  fi
  validate_artifact "$tmp/repo/$subpath" "$subpath" \
    || { err "$name: subpath $subpath is no longer a valid $KIND upstream, skipping"; return 1; }

  copy_artifact "$tmp/repo/$subpath" "$artifact"
  write_sidecar "$name" "$repo" "$subpath" "$ref" "$new_commit" "$category"
  info "$name: updated ${old_commit:0:7} -> ${new_commit:0:7}"
}

cmd_update() {
  local name="" all=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --all)  all=1; shift ;;
      *) die "update: unknown argument '$1'" ;;
    esac
  done

  if [[ "$all" -eq 1 ]]; then
    local n s
    while IFS=$'\t' read -r n s; do
      [[ -f "$s" ]] || continue
      [[ "$(jq -r '.repo // empty' "$s")" ]] || continue
      update_one "$n" || true
    done < <(iter_resources)
    return 0
  fi

  [[ -n "$name" ]] || die "update: --name NAME or --all is required"
  update_one "$name"
}

cmd_delete() {
  local name="" yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --yes)  yes=1; shift ;;
      *) die "delete: unknown argument '$1'" ;;
    esac
  done
  [[ -n "$name" ]] || die "delete: --name NAME is required"
  local artifact; artifact="$(artifact_path "$name")"
  [[ -e "$artifact" ]] || die "$(rel "$artifact") does not exist"

  if [[ "$yes" -ne 1 ]]; then
    local reply
    printf 'Delete %s %s? [y/N] ' "$KIND" "$name" >&2
    read -r reply </dev/tty || reply=""
    [[ "$reply" == "y" || "$reply" == "Y" ]] || { info "aborted"; return 0; }
  fi
  case "$KIND" in
    skill) rm -rf "$artifact" ;;
    agent) rm -f "$artifact" "$(sidecar_path "$name")" ;;
  esac
  info "deleted $(rel "$artifact")"
}

# Read a scalar frontmatter field from a markdown file, joining folded (`>`)
# and indented continuation lines into one space-separated value.
frontmatter_field() {
  local file="$1" field="$2"
  awk -v f="$field" '
    NR == 1 { if ($0 == "---") { infm = 1; next } else { exit } }
    infm && $0 == "---" { exit }
    !infm { next }
    capturing {
      if ($0 ~ /^[[:space:]]+[^[:space:]]/) { sub(/^[[:space:]]+/, ""); val = val (val == "" ? "" : " ") $0; next }
      exit
    }
    $0 ~ "^" f ":" {
      v = $0; sub("^" f ":[[:space:]]*", "", v)
      if (v !~ /^[>|][+-]?$/) val = v
      capturing = 1
    }
    END { print val }
  ' "$file"
}

# One-line "purpose" for a catalog row: the description collapsed to a single
# sentence, pipes escaped for markdown tables, truncated if still long.
purpose_from_description() {
  local desc="$1" purpose
  purpose="$(printf '%s' "$desc" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
  purpose="${purpose#\"}"; purpose="${purpose%\"}"
  # Shield common abbreviations so the first-sentence split below doesn't
  # break on them, then restore the spaces afterwards.
  local sep=$'\x01' abbr
  for abbr in e.g. i.e. etc. vs.; do
    purpose="${purpose//"$abbr" /$abbr$sep}"
  done
  case "$purpose" in
    *". "*) purpose="${purpose%%. *}." ;;
  esac
  purpose="${purpose//$sep/ }"
  purpose="${purpose//|/\\|}"
  if (( ${#purpose} > 160 )); then
    purpose="${purpose:0:157}..."
  fi
  printf '%s' "$purpose"
}

# Render the markdown skills catalog (a standalone skills/README.md with
# category-grouped tables) to stdout.
render_catalog() {
  [[ "$KIND" == "skill" ]] || die "catalog: only supported for --kind skill"
  local data="" name sidecar category desc purpose total
  while IFS=$'\t' read -r name sidecar; do
    [[ -n "$name" ]] || continue
    [[ -f "$RESOURCE_ROOT/$name/SKILL.md" ]] || continue
    category=uncategorized
    [[ -f "$sidecar" ]] && category="$(jq -r '.category // "uncategorized"' "$sidecar")"
    desc="$(frontmatter_field "$RESOURCE_ROOT/$name/SKILL.md" description)"
    purpose="$(purpose_from_description "$desc")"
    [[ -n "$purpose" ]] || purpose="(no description)"
    data+="$category"$'\t'"$name"$'\t'"$purpose"$'\n'
  done < <(iter_resources)
  [[ -n "$data" ]] || { info "no skills found"; return 0; }

  total="$(printf '%s' "$data" | grep -c .)"
  printf '# Skills catalog\n\n'
  printf '%s skills, grouped by the `category` in each skill'\''s `.source.json` sidecar.\n' "$total"
  printf 'Generated by `make skills-catalog` — do not edit by hand (`make skills-doctor` flags a stale file).\n\n'

  # Categories alphabetically, uncategorized last.
  local cats cat first=1
  cats="$(printf '%s' "$data" | cut -f1 | sort -u | grep -vx uncategorized || true)"
  if printf '%s' "$data" | cut -f1 | grep -qx uncategorized; then
    cats="$cats"$'\n'uncategorized
  fi
  while IFS= read -r cat; do
    [[ -n "$cat" ]] || continue
    [[ "$first" -eq 1 ]] || printf '\n'
    first=0
    printf '**%s (%s)**\n\n' "$cat" \
      "$(printf '%s' "$data" | awk -F'\t' -v c="$cat" '$1==c' | grep -c .)"
    printf '| Skill | Purpose |\n|-------|---------|\n'
    printf '%s' "$data" | awk -F'\t' -v c="$cat" \
      '$1==c {printf "| [`%s`](%s/SKILL.md) | %s |\n", $2, $2, $3}'
  done <<<"$cats"
}

# Regenerate the standalone catalog at skills/README.md.
# With --check, don't write: exit 1 if the file is stale.
cmd_catalog() {
  local check=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) check=1; shift ;;
      *) die "catalog: unknown argument '$1'" ;;
    esac
  done
  local catalog="$RESOURCE_ROOT/README.md"
  local tmp; mktmp; tmp="$MKTMP_DIR"
  render_catalog > "$tmp/README.md"

  if [[ "$check" -eq 1 ]]; then
    [[ -f "$catalog" ]] && diff -q "$catalog" "$tmp/README.md" >/dev/null \
      || { err "$(rel "$catalog") is stale (run: make skills-catalog)"; return 1; }
    info "catalog: up to date"
    return 0
  fi
  if [[ -f "$catalog" ]] && diff -q "$catalog" "$tmp/README.md" >/dev/null; then
    info "catalog: up to date"
  else
    cp "$tmp/README.md" "$catalog"
    info "catalog: $(rel "$catalog") regenerated"
  fi
}

# Validate every resource of this kind; exit 1 if any problem is found.
# Skills additionally verify the README catalog block is current.
cmd_doctor() {
  local issues=0 name sidecar md desc
  flag() { printf '%s\n' "$*"; issues=$((issues + 1)); }
  while IFS=$'\t' read -r name sidecar; do
    [[ -n "$name" ]] || continue
    case "$KIND" in
      skill) md="$RESOURCE_ROOT/$name/SKILL.md" ;;
      agent) md="$RESOURCE_ROOT/$name.md" ;;
    esac
    if [[ ! -f "$md" ]]; then
      flag "$name: missing $(rel "$md")"
      continue
    fi
    [[ -n "$(frontmatter_field "$md" name)" ]] \
      || flag "$name: SKILL/agent frontmatter has no 'name'"
    desc="$(frontmatter_field "$md" description)"
    [[ -n "$desc" ]] || flag "$name: frontmatter has no 'description'"
    if [[ ! -f "$sidecar" ]]; then
      flag "$name: unmanaged (no .source.json sidecar)"
    elif [[ "$(jq -r '.category // ""' "$sidecar")" == "" ]]; then
      flag "$name: sidecar has no 'category'"
    fi
  done < <(iter_resources)

  if [[ "$KIND" == "skill" ]]; then
    cmd_catalog --check || issues=$((issues + 1))
  fi
  if [[ "$issues" -gt 0 ]]; then
    err "doctor: $issues issue(s) found"
    return 1
  fi
  info "doctor: all ${KIND}s healthy"
}

# Set/replace the category on an existing resource's sidecar (in place, so it
# survives update). Creates a minimal local sidecar if none exists yet.
cmd_category() {
  local name="" category=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)     name="$2"; shift 2 ;;
      --category) category="$2"; shift 2 ;;
      *) die "category: unknown argument '$1'" ;;
    esac
  done
  [[ -n "$name"     ]] || die "category: --name NAME is required"
  [[ -n "$category" ]] || die "category: --category CAT is required"
  local artifact sidecar
  artifact="$(artifact_path "$name")"
  sidecar="$(sidecar_path "$name")"
  [[ -e "$artifact" ]] || die "$name: no such $KIND"
  if [[ -f "$sidecar" ]]; then
    local tmp; tmp="$(mktemp)"
    jq --arg c "$category" '.category = $c' "$sidecar" > "$tmp" && mv "$tmp" "$sidecar"
  else
    jq -n --arg c "$category" '{repo:null, category:$c}' > "$sidecar"
  fi
  info "$name: category set to '$category'"
}

# --- dispatch --------------------------------------------------------------

[[ $# -ge 2 && "$1" == "--kind" ]] \
  || die "usage: resource-manager.sh --kind {skill|agent} {fetch|list|update|delete} ..."
KIND="$2"; shift 2
configure_kind

[[ $# -ge 1 ]] || die "missing command (expected fetch|list|update|delete)"
cmd="$1"; shift
case "$cmd" in
  fetch)    cmd_fetch    "$@" ;;
  list)     cmd_list     "$@" ;;
  update)   cmd_update   "$@" ;;
  delete)   cmd_delete   "$@" ;;
  category) cmd_category "$@" ;;
  catalog)  cmd_catalog  "$@" ;;
  doctor)   cmd_doctor   "$@" ;;
  *) die "unknown command '$cmd' (expected fetch|list|update|delete|category|catalog|doctor)" ;;
esac
