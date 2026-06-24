---
name: bump-hugo-docsy-versions
description: Use when bumping Hugo, Go, or the Docsy theme in a Hugo+Docsy site that loads Docsy as a Hugo Module via go.mod and pins versions in netlify.toml. Triggers "update go version", "bump docsy", "upgrade hugo", or stale GO_VERSION/HUGO_VERSION.
---

# Bumping Hugo, Go, and Docsy Versions

## Overview

Versions are pinned in **three** places that must stay in sync: `go.mod` (Go directive + module require), the deploy config (e.g. `netlify.toml` — `GO_VERSION` + `HUGO_VERSION` across every `[context.*]`), and the Docsy module version itself.

The non-obvious trap: **`go mod tidy` strips the Docsy `require` lines** because no Go source imports them — Hugo's module system uses `go.mod` but Go's tooling cannot see that.
Use `hugo mod get` for module updates, not `go get` + `go mod tidy`.

## Quick Reference

| Version | Where pinned | How to update |
|---|---|---|
| Docsy theme | `go.mod` `require` | `hugo mod get github.com/google/docsy@vX.Y.Z` |
| Docsy dependencies | `go.mod` `require` | `hugo mod get github.com/google/docsy/dependencies@vA.B.C` |
| Go toolchain (directive) | `go.mod` `go ...` line | `go mod edit -go=X.Y.Z` |
| Go toolchain (deploy config) | `netlify.toml` `GO_VERSION` in every context | manual edit |
| Hugo (deploy config) | `netlify.toml` `HUGO_VERSION` in every context | manual edit |

## Procedure

### 1. Check the current state

```bash
cat go.mod
grep -E '(HUGO|GO)_VERSION' netlify.toml
go version    # local Go
hugo version  # local Hugo (extended build expected)
```

### 2. Look up the right versions

```bash
# Docsy + dependencies — go module proxy is authoritative
curl -s https://proxy.golang.org/github.com/google/docsy/@latest
curl -s https://proxy.golang.org/github.com/google/docsy/dependencies/@latest
```

**Pin Hugo to whatever Docsy itself targets, NOT the absolute latest Hugo release.**
Docsy's `package.json` carries a `hugo_version` field recording the Hugo version that release was tested against:

```bash
gh api "repos/google/docsy/contents/package.json?ref=v<docsy-version>" --jq .content | base64 -d | grep -A1 hugo_version
```

Bumping Hugo past that pin risks breakage.
Hugo 0.158+ wraps the PostCSS pipeline in Node's experimental Permission Model with a restricted filesystem scope, which breaks browserslist's parent-directory search and hangs or fails `hugo --minify`.
Docsy pins `hugo_version` for exactly this reason.

Note: `docsy/dependencies` moves rarely.
Don't assume it has an update just because the main Docsy module does.

### 3. Update Docsy via `hugo mod get` (NOT `go get` + `go mod tidy`)

```bash
hugo mod get github.com/google/docsy@vX.Y.Z
hugo mod get github.com/google/docsy/dependencies@vA.B.C   # only if changed
```

**Why not `go mod tidy`:** It scans Go source files for imports.
There are none for the theme — Hugo resolves modules at build time.
`tidy` will silently strip both `require` lines, leaving an empty `go.mod` that Hugo then refuses to build against.
`hugo mod get` writes both `go.mod` and `go.sum` correctly.

If you already ran `go mod tidy` and lost the requires, recover with the same `hugo mod get` calls — they re-add them.

### 4. Bump the Go directive in go.mod

```bash
go mod edit -go=X.Y.Z   # match local `go version` or the deploy config's GO_VERSION
```

### 5. Sync the deploy config

Update **every** `[context.*]` block in `netlify.toml` (commonly `production`, `deploy-preview`, `branch-deploy`; a site may define additional custom contexts):

```toml
HUGO_VERSION = "<new-hugo-version>"
GO_VERSION   = "<matches go.mod go directive>"
```

Easy to miss: the same pair is repeated in every context — use a single multi-line edit covering all of them, not one edit per context.

### 6. Verify the build

Verify with the `verify-hugo-docsy-build` skill.

### 7. Review and commit

```bash
git diff --stat
git diff go.mod go.sum netlify.toml
```

Expect changes only in `go.mod`, `go.sum`, and the deploy config.
If `public/` or `resources/_gen/` show up they are build artifacts — `.gitignore` should already exclude them; do not add them.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Ran `go mod tidy` after `go get` | `go.mod` requires section is empty | Re-run `hugo mod get` for each module |
| Pinned Hugo to the absolute latest release | `hugo --minify` hangs or errors with `ERR_ACCESS_DENIED` from Node | Pin to whatever Docsy's `package.json` `hugo_version` field says |
| Verified with `hugo --gc --quiet` only | "Looked clean locally" but deploy fails | Run `./build.sh` (see `verify-hugo-docsy-build` skill) |
| Bumped `GO_VERSION` in only one context | Production and previews use different Go versions | Update all contexts |
| Bumped `HUGO_VERSION` in deploy config but not the `go.mod` `go` directive | Local build uses a different toolchain than CI | Keep them aligned |
| Used `go get` instead of `hugo mod get` | Works, but does not refresh Hugo's module cache the same way | Prefer `hugo mod get` |
| Pinned Hugo to non-extended version | SCSS/asset pipeline breaks | Docsy needs Hugo **extended** — most deploy images are extended by default |

## Red Flags — Stop

- About to run `go mod tidy` after touching a module require → don't.
- About to commit only `go.mod` without `go.sum` or vice versa → both update together.
- `hugo --gc` prints warnings about missing partials after a Docsy major bump → check Docsy CHANGELOG before pushing.
- Deploy config diff touches only one context → check the others.
