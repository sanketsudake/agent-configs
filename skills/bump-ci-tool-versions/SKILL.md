---
name: bump-ci-tool-versions
description: Bump the pinned CLI tool versions that GitHub Actions workflows download at runtime (helm, kind, skaffold, cosign, golangci-lint, goreleaser, etc.) — the `*_VERSION:` env vars and the `# vX.Y.Z` comments next to SHA-pinned `uses:` actions. Use for "update workflow tool versions" (also invoked as `workflow-tool-versions`), "CI tool refresh", "bump skaffold/kind/cosign", or processing a Dependabot github-actions PR. Generic to any repo with GitHub Actions workflows.
---

# Bump CI tool versions

Playbook for refreshing the CLI tool versions a repo's GitHub Actions workflows pin.
Optimised for **isolating regressions**: each tool lands as its own commit, so CI-failure attribution is one `git blame`.

Project-agnostic.
For this repo's known tool inventory, which workflows pin what, and any deliberately-stale pins (e.g. an old major kept on purpose to test an upgrade path), read its `CLAUDE.md` and `.claude/resources/` — re-discover dynamically (Phase 0) rather than trusting any snapshot.

## When to invoke

Trigger phrases: "update workflow tool versions", "bump skaffold/kind/cosign/helm", "what's outdated in our workflows", "process the dependabot github-actions PR", "CI tool refresh".

Skip if the user names a single tool and version — just edit and commit.

## Scope (priority order)

1. **Primary — `env:`-block `*_VERSION:` vars.**
   Versions the workflow downloads at runtime; the main scope.
   Dependabot does NOT touch these.
2. **Secondary — `# vX.Y.Z` comments next to SHA-pinned `uses:` actions.**
   Dependabot usually bumps these on a schedule, so a manual pass is catch-up if Dependabot is behind/paused.
3. **Tertiary — version matrices** (e.g. a `kindversion:` of k8s node images).
   Tied to the tool's support window; bump only when the underlying binary supports the newer target.

Out of scope: floating constraints (`with: version: "~> v2"` — no pin to bump), and tool versions living in `Makefile`/`hack/`/`Dockerfile`/release config (those go with the build code, not the runners).

## Phase 0 — Baseline

1. Branch off the default branch.
   **Check for a stale merged collision first** (a date-stamped name avoids it): `git checkout <default> && git checkout -b ci/tool-versions-<YYYY-MM-DD>`.
   After a recent merged sweep, most `*_VERSION:` vars already being at latest is normal, not a discovery failure.
2. Inventory dynamically — don't trust any snapshot: ```bash grep -rnE "^\s*[A-Z_]+_VERSION:" .github/workflows/ grep -rnE "uses:.*@[a-f0-9]{40} # v" .github/workflows/   # SHA-pinned actions w/ version comments ```
3. Resolve each tool to its upstream repo and fetch latest (`gh api` authenticates automatically): ```bash for repo in <owner1>/<tool1> <owner2>/<tool2>; do echo "$repo -> $(gh api "repos/$repo/releases/latest" --jq '.tag_name')" done ```

## Phase 1 — Decide what to bump

- **Patch** (`vX.Y.Z → Z+n`): take unconditionally; read notes only if it skips many patches.
- **Minor** (`vX.Y → Y+1`): read upstream notes for breaking-ish changes — linters and build tools periodically rename/drop config keys or profiles.
- **Major** (`vX → X+1`): don't lump into a sweep; open a separate branch with its own validation.

Flag deliberate stale pins the repo documents (e.g. an old major kept to test an upgrade path, or a matrix entry intentionally lagging) — leave them unless the user says otherwise.

## Phase 2 — Per-tool workflow

```bash
$EDITOR .github/workflows/<file>.yaml          # edit the *_VERSION line(s)

# Validate the YAML still parses. PyYAML may be absent on macOS; ruby ships with macOS:
ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f) }; puts "YAML OK"' .github/workflows/<file>.yaml
# Fallback: python3 -c "import yaml,sys; [yaml.safe_load(open(f)) for f in sys.argv[1:]]" <files>

git add .github/workflows/
git commit -m "Bump <tool> v<old> -> v<new>"
```

If a var lives in **multiple files with the same intent** (e.g. "latest stable kind" in two workflows), bump them in one commit.
If intents differ (a tool pinned old in one workflow on purpose), keep separate commits.

When the user asks to bump a **SHA-pinned action**:
1. Resolve the new tag to its commit SHA (the pin is a 40-hex SHA, not the tag): `gh api repos/<owner>/<repo>/commits/<tag> --jq '.sha'`.
   Update both the `@<sha>` and the trailing `# vX.Y.Z` comment.
2. One action often appears in several files — replace every occurrence with the identical new `@<sha> # vX.Y.Z` and commit together.
   `Edit` with `replace_all` per file is reliable; a shell `perl -pi -e` one-liner with `#`/spaces silently no-ops, so re-`grep` to confirm.

## Phase 3 — Verification

There's no local equivalent for "did this workflow still pass" — CI is the test.
1. `git log --oneline <default>..HEAD` to review the per-tool commits.
2. Push and let CI run on the PR.
3. If one tool's commit breaks CI, revert that single commit without touching the rest — the point of the per-tool structure.

## Pitfalls

- **Config-schema migrations on minor bumps** (golangci-lint, skaffold, etc.): a bump can fail CI with a config-validation error.
  Run the tool's own config-verify against the new binary locally (`golangci-lint config verify`, `skaffold diagnose --profile <p>`) and migrate deprecated keys rather than disabling config.
- **A version var read by multiple jobs**: confirm every consumer still reads the env var (not a hardcoded version) after editing — some tools are installed twice in one workflow.
- **Dependabot overlap.**
  Dependabot groups *action* SHA bumps but not runtime `*_VERSION:` vars, so the primary scope rarely overlaps.
  Before declaring a SHA-pinned action "behind", check for an open Dependabot PR: `gh pr list --author "app/dependabot" --state open`.
  If a `github-actions` group PR already bumps it, don't duplicate — flag it in the summary so the user reconciles (whichever merges first, the other rebases).

## Canonical outline

```
1. branch ci/tool-versions-<YYYY-MM-DD>
2. grep .github/workflows/ for *_VERSION vars + SHA-pinned uses
3. gh api repos/<owner>/<repo>/releases/latest per tool
4. per tool (patch/minor; defer majors): edit, validate YAML, commit; group same-intent files
5. push; let CI verify
6. summarize: bumps, deferred majors, flagged intentional stale pins, Dependabot overlap
```
