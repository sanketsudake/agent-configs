---
name: triage-gh-backlog
description: Use when scrubbing or triaging a GitHub repo's open issue/PR backlog — e.g. "go through all open issues and PRs and see what can be closed", "scrub the outstanding issues", "close stale/duplicate items" — closing stale/duplicate/already-shipped/EOL items and categorizing the rest (type, area, priority) like a product manager. Use for one-off backlog cleanups or a recurring triage cadence. Backed by gitcrawl (local SQLite mirror, no API-quota burn). Portable across OSS repos via --repo + a per-repo config.
---

# triage-gh-backlog

A repeatable, low-risk pipeline to scrub a long-neglected GitHub backlog.
It mirrors all issues/PRs into local SQLite with **gitcrawl**, applies a deterministic rule engine to decide a *disposition* per thread (close-stale / close-duplicate / close-implemented / close-eol / pr-archive / needs-info / keep+categorize), produces a reviewable report, and only then — gated and capped — applies the approved actions to GitHub via `gh`.

**Core principle: decide locally and cheaply (repeatable, no writes); apply to GitHub separately, gated, and capped.** gitcrawl's own `close-thread`/`close-cluster` are LOCAL-only (they hide items from future runs; they never touch GitHub).
All real closing/labeling/commenting goes through `gh` in the `apply` stage.

This skill is project-agnostic: everything is parameterized by `--repo owner/name` and a per-repo `config.<owner>__<repo>.toml`.
Point it at any repo.

## When to use

Not for: reading a single issue (`gh issue view`), or anything needing GitHub *write* beyond close/label/comment (milestones, transfers — do by hand).

## Prerequisites

`bash scripts/scrub.sh doctor` checks them: **gitcrawl** (`brew install openclaw/tap/gitcrawl` then `gitcrawl init`), **gh** (authenticated), **python3 3.11+**, **sqlite3**.
No OpenAI key — keyword/FTS-only.

## The pipeline

Five idempotent stages, each reading/writing a per-repo workdir (`~/.cache/issue-pr-scrub/<owner>__<repo>/` by default; override via config).
Run them via `scripts/scrub.sh`:

| Stage | Command | Writes GitHub? | Output |
| --- | --- | --- | --- |
| sync | `scrub.sh sync --repo R [--full]` | no (reads GitHub) | populates gitcrawl SQLite |
| extract | `scrub.sh extract --repo R` | no | `threads.jsonl` |
| triage | `scrub.sh triage --repo R` | no | `triage.jsonl` |
| report | `scrub.sh report --repo R` | no | `report.md`, `triage.csv`, `apply-plan.jsonl` |
| apply | `scrub.sh apply --repo R --auto\|--from F [--execute]` | **yes (gated)** | `ledger.jsonl` |

Plus `scrub.sh protect --repo R [--execute]` — adds `keep-open` to the numbers in `keepers.txt` (gated; dry-run default).

`scrub.sh run --repo R [--full]` chains sync→extract→triage→report (never writes).
Use `--full` on the first run (full backfill); omit it after (incremental, with closed-sweep).

**Read the detailed stage contract in `resources/pipeline.md` before running.**

For `review`-tier items: copy the ones you approve from `apply-plan.jsonl` into `approved.jsonl`, then `apply.py --from approved.jsonl --execute`.

## Re-reviewing the stale pile (don't bulk-close blindly)

`close-stale` is purely age-based and is usually the biggest bucket — treat it as "needs eyes," not "safe to close."
Every row is enriched with type/area/priority/engagement, and `report.py` emits **`stale-review.csv`** sorted by signal (highest reactions+comments, feature/bug first) so keepers float to the top.

```bash
# 1) skim stale-review.csv; put numbers worth keeping into keepers.txt (one per line, '# notes' allowed)
# 2) re-run — keepers become skip and drop out of the apply-plan (instant, no re-sync)
bash scrub.sh triage --repo R && bash scrub.sh report --repo R
# 3) optional: make the protection visible upstream
bash scrub.sh protect --repo R --execute       # adds keep-open to keepers.txt items
# 4) close only what's left
bash scrub.sh apply --repo R --auto --execute
```

## How it decides

The rule engine, taxonomy, and write playbook are documented in:
- `resources/triage-rules.md` — every disposition, its heuristic, its tier
- `resources/labels.md` — full label taxonomy + mapping + proposed extensions
- `resources/write-actions.md` — gh write playbook, comment templates, safety gates
- `resources/gitcrawl-reference.md` — the gitcrawl commands + SQLite schema this skill relies on

## Safety gates (apply stage) — non-negotiable

Enforced in `apply.py` every run, never to be bypassed: dry-run by default (no `--execute` ⇒ prints only), per-run write cap (`apply.max_per_run`, default 25, with pacing), tier gate (`--auto` touches only `tier=auto`; `review` requires `--from <curated>`), staleness re-check (skips anything closed or touched since extract — re-run the pipeline), protected-label re-check, and ledger dedup (a recorded `(number, action)` is never repeated).

## Per-repo config

Copy `scripts/config.example.toml` to `scripts/config.<owner>__<repo>.toml` and tune the `[areas]`/`[types]`/`[versions]` tables — those are the only repo-specific settings.
`scripts/.gitignore` ignores every `config.*.toml` except the example, so your per-repo configs stay local and never get committed.
A worked example for `fission/fission` ships alongside as a reference (also git-ignored).
