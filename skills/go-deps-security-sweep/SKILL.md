---
name: go-deps-security-sweep
description: Run a grouped, bisectable Go dependency security sweep. Use when the user asks to upgrade outdated/vulnerable Go deps, run a dep security pass, or process govulncheck/Dependabot findings. Lands one commit per logical dependency group on a dedicated branch so any regression is attributable and revertable. Generic to any Go module.
---

# Go dependency security sweep

Playbook for upgrading outdated Go dependencies as a security pass.
Optimised for **isolating failures**: each logical group of related deps lands as a separate commit, so `git bisect` can attribute any regression to one group, then to one dep within it.

Project-agnostic.
For this repo's exact dependency groups and their version-coupling rules (e.g. which deps must move in lockstep, any `replace`/`exclude` directives, codegen to re-run after a bump), read the project's `CLAUDE.md` and `.claude/resources/` — those carry the couplings that MVS will otherwise get wrong.

## When to invoke

Trigger phrases: "upgrade outdated Go deps", "security sweep on go.mod", "run govulncheck and fix what's found", "bump dependencies for security".

Skip for a single named bump — that's `go get <pkg>@<ver>` + tidy + lint + commit, no grouping.

## Phase 0 — Baseline

1. Branch off the default branch.
   **Check for a stale collision first** — a prior month's sweep branch often still exists locally and on `origin` after its PR merged, so a reused name fails with "already exists" and its diff looks like a huge *reverse* (the default branch moved on).
   If `git rev-parse --verify <branch>` succeeds, run `gh pr list --head <branch> --state all`; a MERGED PR means it's leftover — don't reuse it.
   Use a **date-stamped** name: `git checkout <default> && git checkout -b deps/security-sweep-<YYYY-MM-DD>`.
2. Install the scanner if missing: `go install golang.org/x/vuln/cmd/govulncheck@latest`.
3. Capture the baseline: `govulncheck ./... | tee /tmp/govulncheck-before.txt`.
   The "affected by N vulnerabilities" line and each "Fixed in:" version dictate minimum targets.
4. List outdated **direct** deps: ```bash go list -m -u -json all 2>/dev/null | python3 -c " import json, sys buf=''; mods=[] for line in sys.stdin: buf += line if line.rstrip()=='}': try: mods.append(json.loads(buf)); buf='' except: pass for m in mods: if not m.get('Indirect') and m.get('Update'): print(f\"{m['Path']:<70} {m['Version']:<20} -> {m['Update']['Version']}\") " ```

## Phase 1 — Group the upgrades (lowest risk first)

Bucket the outdated deps by ecosystem so related modules move together.
A typical ordering, lowest-blast-radius last to fail loudly first:

1. **Platform/SDK core** (e.g. the `k8s.io/*` family) — all to the same patch/minor; usually lowest risk on a patch bump.
2. **Framework/controller tooling** built against that core — these often break API consumers across a minor.
3. **Observability** (e.g. all `go.opentelemetry.io/*`) — core + contrib use linked version lines; bump together.
4. **Transport** (`google.golang.org/grpc`, `golang.org/x/net`) — commonly paired in CVE fixes; often pulled up transitively by the observability bump, so check before bumping explicitly.
5. **Everything else** with a CVE or minor available — lowest blast radius, leave for last.

**Lockstep groups:** when a dep compiles against a specific version of another (a controller framework against a platform-core minor, plus anything that embeds either), they are version-locked and must land as **one** commit — MVS will otherwise pick an incompatible mix.
The repo's resources document which groups are coupled here; treat that as authoritative over the generic ordering above.

If a dep carries a CVE the baseline flagged, keep the group order but name the advisory in the commit message.

## Phase 2 — Per-group workflow

```bash
go get <pkg1>@<ver1> <pkg2>@<ver2> ...   # all deps in the group in one command
go mod tidy
go build ./pkg/... ./cmd/...              # scope away test fixtures — see pitfall
<repo lint/build/test gate>               # the project's make target, e.g. make code-checks
```

If build + gate pass, commit:
```
Bump <group name> (<pkg@ver>, <pkg@ver>)

<One-line rationale; name the GO-YYYY-NNNN advisory if this closes one.>
```

If the group fails, bisect **within** it: drop one dep at a time from the `go get`, re-run tidy+build+gate, pin back the offender, commit the rest.
Don't skip the whole group — a partial group is still progress.

## Phase 3 — Final verification (once, after all groups)

1. `git diff <default> -- go.mod | head -80` — sanity-check the direct-deps diff matches the groups.
2. Run the repo's **full** gate (lint + tests + any build).
3. `govulncheck ./... | tee /tmp/govulncheck-after.txt`; diff against the baseline and put "CVEs closed" in the PR description.

## Pitfalls learned the hard way

- **Retracted/accidental high-version tags.**
  A transitive dep can push a bogus high tag (e.g. `v1.20.99` on a project actually on the `v0.x` line); `go get` then picks it as "latest" and `tidy` warns `retracted by module author`.
  Fix: `exclude <pkg> <bad-version>` + explicit `go get <pkg>@<correct-latest>`.
  (Prefer `replace`/`exclude` per the repo's existing directive style.)
- **`go build ./...` vs test fixtures.**
  Repos often contain `package main` fixtures with no `main` (test data); `go build ./...` fails on them on the default branch too.
  Scope the compile check to the real source trees (`./pkg/... ./cmd/...`).
- **Docker-dependent tests** (e.g. a package using `ory/dockertest`/MinIO) fail without a running daemon — environmental, not a dep regression.
  Confirm by checking out `go.mod`+`go.sum` from the default branch and re-running just that package.
- **Cache/disk exhaustion after a platform-core minor bump.**
  A core bump invalidates the whole `$(go env GOCACHE)`, so the first test run recompiles everything and the cache balloons (tens of GB).
  On a near-full disk the symptom is a cascade of `[build failed]` with `No space left on device`/`dsymutil failed` across unrelated packages — NOT a dep regression.
  Check `df -h /` and `du -sh $(go env GOCACHE)`; clear with `go clean -cache` and re-run.
- **Test output piped through `tail` hides the failing package.**
  A failing package prints `FAIL` near the end, but the package name is hundreds of lines up.
  Capture full output (`> /tmp/out.txt 2>&1`) and `grep -nE '^(FAIL|--- FAIL)'` before concluding anything.
- **`git stash pop` hazard.**
  A clean tree makes `git stash` a silent no-op, so a later `git stash pop` unstashes a *pre-existing* WIP entry from another session and can conflict.
  Run `git stash list` before any pop; recover a contaminated tree with `git checkout HEAD -- <files>`.

## Out of scope

- Go toolchain version bumps.
- Indirect-only deps (let `go mod tidy` carry them forward).
- Major-version bumps (`v1 → v2`) — those need dedicated review, not a batch sweep.

## Canonical outline

```
1. branch deps/security-sweep-<YYYY-MM-DD>  (check for stale merged collision first)
2. govulncheck ./... | tee /tmp/govulncheck-before.txt
3. group outdated direct deps (lowest risk first; honour the repo's lockstep groups)
4. per group: go get … ; go mod tidy ; go build ./pkg/... ./cmd/... ; <repo gate>
            on failure bisect within the group; on success commit
5. full repo gate
6. govulncheck ./... | tee /tmp/govulncheck-after.txt ; diff vs baseline
7. summarize: commits, CVEs closed, deferred groups + upstream blocker
```
