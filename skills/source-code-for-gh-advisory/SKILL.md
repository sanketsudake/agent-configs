---
name: source-code-for-gh-advisory
description: Use when the user wants to obtain, inspect, or reproduce the vulnerable source code referenced by a GitHub Security Advisory (GHSA-xxxx / CVE) — including security research, PoC reproduction, patch diffing, or auditing the affected file/function.
---

# Source Code For a GitHub Advisory

## Overview

A GitHub Security Advisory pins down exactly which repository, version range, and (usually) file/function are vulnerable.
To analyze it locally you need the source tree at a commit where the bug is still present — *not* the patched default branch.
This skill fetches advisory metadata with `gh`, picks the last vulnerable tag, and shallow-clones only that tag.

## When to Use

- User pastes a GHSA URL (e.g. `https://github.com/<owner>/<repo>/security/advisories/GHSA-xxxx-xxxx-xxxx`) or a CVE that maps to one.
- User says "clone the affected version", "get the vulnerable code", "reproduce the advisory", "diff the fix", or similar.
- Any security-review / patch-analysis task that needs the pre-fix tree.

**Do NOT use** for general bug reports, non-security issues, or when the user explicitly wants the patched/current code.

## Workflow

1. **Resolve advisory metadata via `gh`** — never scrape the HTML page.
2. **Pick the last vulnerable tag** from the version range.
3. **Shallow-clone only that tag** (`--depth 1 --branch <tag>`).
4. **Verify** the vulnerable file/symbol exists in the checkout.
5. **Report** path, tag, and confirmed vulnerable location.

## Step 1 — Fetch advisory metadata

Prefer the repo-scoped endpoint; fall back to the global one:

```bash
GHSA="GHSA-xxxx-xxxx-xxxx"
OWNER="<owner>"; REPO="<repo>"

gh api "repos/$OWNER/$REPO/security-advisories/$GHSA" \
  || gh api "/advisories/$GHSA"
```

Extract the fields you need with `jq`:

```bash
gh api "/advisories/$GHSA" --jq '{
  repo: .repository.full_name // "<owner>/<repo>",
  summary,
  severity,
  vuln_range: .vulnerabilities[0].vulnerable_version_range,
  patched:    .vulnerabilities[0].patched_versions,
  files:      [.description | scan("`[^`]+\\.[a-zA-Z]+`")]
}'
```

Key fields:

| Field | Why it matters |
|---|---|
| `vulnerabilities[].vulnerable_version_range` | Tells you which tags are affected (e.g. `>= 0.86.0, < 1.7.0`). |
| `vulnerabilities[].patched_versions` | Tells you the first fixed tag — clone **the tag just below this**. |
| `description` | Usually names the vulnerable file(s) and function(s). Capture them for Step 4. |
| `html_url` / `repository.full_name` | The repo to clone. |

If the advisory does not name the repo explicitly, infer it from the advisory URL the user pasted.

## Step 2 — Pick the last vulnerable tag

List tags via `gh` (no clone needed) and pick the highest one strictly less than `patched_versions`:

```bash
gh api "repos/$OWNER/$REPO/tags" --paginate --jq '.[].name' \
  | sort -V -r | head -40
```

Rules of thumb:
- `patched_versions: 1.7.0` and range `< 1.7.0` → use `v1.6.1` (or whatever the highest `1.6.x` tag is).
- If the repo prefixes tags with `v`, keep the prefix when cloning.
- If a specific commit is named in the advisory description, prefer that commit over a tag.

## Step 3 — Shallow-clone the single tag

**Always** clone only the affected tag, with depth 1. Do not clone full history or multiple versions:

```bash
TAG="v1.6.1"
DEST="$HOME/<chosen-path>/$REPO"

git clone --depth 1 --branch "$TAG" \
  "https://github.com/$OWNER/$REPO.git" "$DEST"
```

Notes:
- `--branch` accepts tag names too — this lands you in detached HEAD at that tag with one commit of history.
- If you need to diff against the patched version later, fetch *that one* tag on top (still shallow):
  ```bash
  git -C "$DEST" fetch --depth 1 origin tag v1.7.0
  git -C "$DEST" diff v1.6.1 v1.7.0 -- path/to/file
  ```
- Ask the user where to clone before creating directories under `$HOME` if the location isn't obvious from context.

## Step 4 — Verify the vulnerable code is present

Use the file/function names captured from the advisory description:

```bash
# File exists?
ls "$DEST/<path/from/advisory>"

# Vulnerable snippet present? Match a distinctive line from the advisory.
grep -n '<distinctive-substring>' "$DEST/<path/from/advisory>"
```

If the file is missing or the snippet doesn't match, you picked the wrong tag — re-check `vulnerable_version_range` and try the next-lower tag.

## Step 5 — Report back

Tell the user:
- Clone path
- Tag + commit short SHA (`git -C "$DEST" rev-parse --short HEAD`)
- Confirmed vulnerable `path:line`
- Advisory id + one-line summary

## Quick Reference

```bash
GHSA="GHSA-xxxx-xxxx-xxxx"
OWNER="acme"; REPO="widget"
DEST="$HOME/personal/$REPO"

# 1. Metadata
gh api "/advisories/$GHSA" --jq '.vulnerabilities[0] | {vuln_range: .vulnerable_version_range, patched: .patched_versions}'

# 2. Tags
gh api "repos/$OWNER/$REPO/tags" --paginate --jq '.[].name' | sort -V -r | head

# 3. Shallow clone the last vulnerable tag
git clone --depth 1 --branch "v1.6.1" "https://github.com/$OWNER/$REPO.git" "$DEST"

# 4. Verify
grep -n 'authorize(user, "read"' "$DEST/server/routes/api/shares/shares.ts"
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Cloning the default branch | The fix is already merged — vulnerable code is gone. Always check out a tag *below* `patched_versions`. |
| Cloning full history | Wastes bandwidth and disk. Use `--depth 1 --branch <tag>`. |
| Listing tags by cloning first | Use `gh api repos/<o>/<r>/tags` instead — no clone needed to pick the tag. |
| Guessing the affected file | The advisory description almost always names it. Parse it from `gh api` output; don't scrape HTML. |
| Using `git checkout <tag>` after a non-tag shallow clone | `git fetch --depth 1 origin tag <tag>` first, or just re-clone with `--branch <tag>`. |
| Ignoring CVE-only references | If the user gives a CVE, resolve it: `gh api /advisories?cve_id=CVE-YYYY-NNNNN`. |

## Red Flags

- About to run `git clone` without `--depth 1` → stop, add the flag.
- About to run `git clone` without `--branch <tag>` → stop, pick the tag first.
- Cloning more than one version "just in case" → don't. Fetch the second tag into the existing clone only if a diff is actually requested.
- About to `curl` the advisory HTML page → use `gh api` instead.
