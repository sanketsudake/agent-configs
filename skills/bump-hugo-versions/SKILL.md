---
name: bump-hugo-versions
description: Use when bumping Hugo, Go, or a theme loaded as a Hugo Module via go.mod, with versions pinned in a deploy config (netlify.toml or a GitHub Actions workflow). Triggers "update go version", "bump the theme", "upgrade hugo".
---

# Bumping Hugo, Go, and Theme Versions

Versions are pinned in **three** places that must stay in sync: `go.mod` (Go directive + module require), the deploy config (e.g. `netlify.toml` `[context.*]` blocks **or** `HUGO_VERSION`/`GO_VERSION` env in a GitHub Actions workflow such as `.github/workflows/publish.yml`), and the theme module version itself.

The non-obvious trap: **`go mod tidy` strips the theme `require` lines** because no Go source imports them — Hugo resolves modules at build time, but Go's tooling cannot see that.
Use `hugo mod get` for module updates, not `go get` + `go mod tidy`.

## Quick Reference

| Version | Where pinned | How to update |
|---|---|---|
| Theme module | `go.mod` `require` | `hugo mod get <theme-module>@vX.Y.Z` |
| Theme deps module (if any) | `go.mod` `require` | `hugo mod get <theme-deps-module>@vA.B.C` |
| Go toolchain (directive) | `go.mod` `go ...` line | `go mod edit -go=X.Y.Z` |
| Go toolchain (deploy config) | `netlify.toml` `GO_VERSION` in every context, or GH Actions `GO_VERSION` env | manual edit |
| Hugo (deploy config) | `netlify.toml` `HUGO_VERSION` in every context, or GH Actions `HUGO_VERSION` env | manual edit |

e.g. Docsy is `github.com/google/docsy`; Congo is `github.com/jpanther/congo/v2`.

## Procedure

### 1. Check the current state

```bash
cat go.mod
grep -E '(HUGO|GO)_VERSION' netlify.toml   # or the relevant GH Actions workflow
go version    # local Go
hugo version  # local Hugo (extended build expected)
```

### 2. Look up the right versions

```bash
# Theme module — go module proxy is authoritative
curl -s https://proxy.golang.org/<theme-module>/@latest
curl -s https://proxy.golang.org/<theme-deps-module>/@latest   # if the theme ships one
```

**Pin Hugo to whatever the theme itself targets, NOT the absolute latest Hugo release.**
If the theme records a tested Hugo version (e.g. in a `package.json` `hugo_version` field), pin to it — bumping Hugo past that risks breakage:

```bash
# Check the theme's repo for a recorded hugo_version (example: look in package.json at the theme's release tag)
gh api "repos/<theme-owner>/<theme-repo>/contents/package.json?ref=v<theme-version>" --jq .content | base64 -d | grep -A1 hugo_version
```

See the `verify-hugo-build` skill for the PostCSS/Node 0.158+ caveat — it is why themes pin a tested Hugo version.

Note: dependency sub-modules move rarely.
Don't assume they have an update just because the main theme module does.

### 3. Update the theme via `hugo mod get` (NOT `go get` + `go mod tidy`)

```bash
hugo mod get <theme-module>@vX.Y.Z
hugo mod get <theme-deps-module>@vA.B.C   # only if changed and the theme ships one
```

`hugo mod get` writes both `go.mod` and `go.sum` correctly.
If you already ran `go mod tidy` and lost the requires, recover with the same `hugo mod get` calls — they re-add them.

### 4. Bump the Go directive in go.mod

```bash
go mod edit -go=X.Y.Z   # match local `go version` or the deploy config's GO_VERSION
```

### 5. Sync the deploy config

**netlify.toml:** Update **every** `[context.*]` block (commonly `production`, `deploy-preview`, `branch-deploy`; a site may define additional custom contexts):

```toml
HUGO_VERSION = "<new-hugo-version>"
GO_VERSION   = "<matches go.mod go directive>"
```

**GitHub Actions workflow** (e.g. `.github/workflows/publish.yml`): Update `HUGO_VERSION` and `GO_VERSION` env vars wherever they are defined (top-level `env:`, per-job `env:`, or step `with:`/`env:` blocks).

Easy to miss: the same pair may be repeated in multiple contexts or jobs — use a single multi-line edit covering all of them, not one edit per context.

### 6. Verify the build

Verify with the `verify-hugo-build` skill.

### 7. Review and commit

```bash
git diff --stat
git diff go.mod go.sum netlify.toml   # or the relevant workflow file
```

Expect changes only in `go.mod`, `go.sum`, and the deploy config.
If `public/` or `resources/_gen/` show up they are build artifacts — `.gitignore` should already exclude them; do not add them.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Ran `go mod tidy` after `go get` | `go.mod` requires section is empty | Re-run `hugo mod get` for each module |
| Pinned Hugo to the absolute latest release | `hugo --minify` hangs or errors with `ERR_ACCESS_DENIED` from Node | Pin to the Hugo version the theme was tested against (check the theme's recorded `hugo_version` if available) |
| Verified with `hugo --gc --quiet` only | "Looked clean locally" but deploy fails | Run the full build (see `verify-hugo-build` skill) |
| Bumped `GO_VERSION` in only one context | Production and previews use different Go versions | Update all contexts / workflow jobs |
| Bumped `HUGO_VERSION` in deploy config but not the `go.mod` `go` directive | Local build uses a different toolchain than CI | Keep them aligned |
| Used `go get` instead of `hugo mod get` | Works, but does not refresh Hugo's module cache the same way | Prefer `hugo mod get` |
| Pinned Hugo to non-extended version | SCSS/asset pipeline breaks | Most themes need Hugo **extended** — most deploy images are extended by default |
| Committed `go.mod` without `go.sum` (or vice versa) | Build fails on a fresh checkout | They update together — commit both |
| Missing-partial warnings after a theme major bump | Layout silently broken | Check the theme CHANGELOG before pushing |
