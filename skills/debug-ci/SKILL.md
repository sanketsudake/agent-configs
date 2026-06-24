---
name: debug-ci
description: Triage and root-cause a failing GitHub Actions CI run on a PR efficiently. Use when CI is red on an open PR, a check needs triaging, the user asks "why is X failing in CI" / "a test failed, can you check", or after a push to confirm a failure is real (also reached by the older name `debug-github-ci`). Optimised for separating real regressions from pre-existing noise and getting the failing line with the cheapest log fetch first. Pairs with watch-ci for the push→monitor loop.
---

# Debug CI failures

A playbook for turning a red CI run into a root cause without burning hours.
Two ideas do most of the work: **separate noise from regression before reading any log**, and **escalate log fetches cheapest-first**.

This skill is project-agnostic.
For repo-specific failure patterns (known-flaky checks, build-pipeline quirks, label/permission gotchas), read the project's `CLAUDE.md` and anything under its `.claude/resources/` before pattern-matching — those carry the symptoms this repo hits repeatedly.

## When to invoke

Trigger phrases: "CI failed on PR #X", "investigate the failed checks", "why are the tests red", "the pipeline is broken on my branch", "did CI pass after the push".

Skip if the user already knows the root cause and wants a specific fix applied — that's an edit + commit, no triage.

## Phase 0 — Separate noise from regression (do this first)

1. List the PR's checks; don't read logs yet, just see who's red: ```bash gh pr checks <PR> --json name,bucket,state,link \ --jq '.[] | select(.name != null) | "\(.bucket)\t\(.name)\t\(.link)"' ``` `bucket` is one of `pass | fail | pending | skipping`.

2. Cross-check against the default branch.
   If the same check is also failing there, it is **pre-existing noise** and this playbook does not apply to it: ```bash gh run list --branch <default-branch> --workflow=<ci>.yaml --limit 5 \ --json conclusion,headSha,databaseId,createdAt gh api repos/<owner>/<repo>/commits/<sha>/status \ --jq '.statuses[] | {context, state, description}'   # external checks (coverage, license, etc.) ```

3. Cross out the repo's known stickers.
   The project's `CLAUDE.md`/resources usually list checks that are red on the default branch by policy (license/compliance scanners, tests needing a local Docker daemon, etc.) — don't chase those.

4. Default branch green + PR red on a check ⇒ real regression.
   Continue.

## Phase 1 — Get the failing line (cheapest first)

Escalate only if the previous step didn't surface the failing line.

| Step | Command | Notes |
|---|---|---|
| 1 | `gh run view <runId> --log-failed` | Failed steps only. Blocked while other jobs in the run are still pending. |
| 2 | `gh api repos/<owner>/<repo>/actions/jobs/<jobId>/logs` | Per-job; works mid-run. `<jobId>` is in the `link` URL from `gh pr checks`. |
| 3 | `gh api repos/<owner>/<repo>/commits/<sha>/status` | External/run-level checks (coverage, license). |
| 4 | `gh run download <runId> -n <artifact-name>` | Test diagnostics, pod logs, profiles — the big artifact for integration-test failures. List first: `gh api repos/<owner>/<repo>/actions/runs/<runId>/artifacts --jq '.artifacts[] | {name, size_in_bytes}'`. |

Filter aggressively on first pass:
```bash
grep -E '(FAIL|--- FAIL|fatal:|panic|error:|Error:|denied|connection refused|i/o timeout|context deadline exceeded)'
```

Don't pull the full run archive (`gh run view <runId> --log`) unless steps 1–3 didn't surface it — it's tens of MB.

## Phase 2 — Pattern-match the symptom

Match the error string against the project's documented failure patterns (its `CLAUDE.md` / `.claude/resources/`) before reading the whole log — most repos recycle the same handful of failure modes (network/connectivity, filesystem/permissions, build pipeline, lint/dependency).
Generic language-agnostic ones worth knowing:

- `dial tcp <ip>:<port>: i/o timeout` between in-cluster pods → a NetworkPolicy drop or a selector mismatch, OR a service not yet ready.
- `connection refused` to `127.0.0.1:<port>` in a test runner → a `kubectl port-forward` / server-startup race; usually a flake, re-run before fixing.
- `404` from an upstream URL (`raw.githubusercontent.com/...`) → broken test fixture URL, not a regression.
- `printf: non-constant format string (govet)` → pass `format, args...` directly, or wrap a dynamic string as `"%s", str`.
- `invalid version: unknown revision vX.Y.Z` → the module path moved or the tag was retracted; check the upstream `releases/latest` and actual git tags.

## Phase 3 — Verify the hypothesis before pushing

1. **Confirm which binary actually ran.**
   Not every image is rebuilt per-PR — some are pre-built and pulled from a registry.
   If logs show old behaviour while your source has the fix, you may be looking at a pre-built image, not your PR's build.
   Compare the `caller`/version field in logs against your local source line numbers; the project's resources usually document which images are per-PR vs pre-built.
2. **Read the source at the cited line before iterating on a flake.**
   After two failed timing-based guesses, stop guessing and read the code path that produces the symptom.
3. **Sanity-test locally** for the affected scope only (lint, focused tests, chart render) — full suites are CI's job, not yours.

## Phase 4 — Push and re-check

After pushing the fix, hand off to the **watch-ci** skill to monitor checks to terminal state instead of busy-polling.
If a check flips back to red after a fix, **don't push another fix immediately** — restart Phase 1 with the new logs.
The new failure is often a different root cause exposed by the previous fix; reusing the old hypothesis wastes a CI cycle.

## Out of scope

- Fixing the underlying business logic of a failing test — once the *cause* is identified, the code change is a normal edit-test-commit.
- Forensic analysis of already-merged breakage on the default branch — reverts/hotfixes have their own flow.

## Canonical outline

```
0. gh pr checks <PR>; gh run list --branch <default> --limit 5  → cross out noise
1. gh run view <runId> --log-failed | grep -E '<patterns>'      → escalate only if needed
2. match error string against the project's documented failure patterns
3. read source at cited line; confirm which binary ran; focused local test
4. push; hand to watch-ci; on red restart Phase 1 with fresh logs
```
