---
name: readwise-second-brain-sync
description: >
  Sync Readwise highlights and Reader documents into the second-brain vault's
  raw/ folder in Obsidian-Web-Clipper format. Use when the user says "sync
  readwise", "pull my readwise highlights", "update raw/ from reader", or wants
  their reading library reflected in the wiki (triggers: readwise sync, reader
  sync, import highlights). Sync only — follow with /second-brain-ingest.
allowed-tools: Bash Read Glob Grep
---

# Readwise → Second-Brain Sync

Deliver Readwise/Reader content into the vault's `raw/` folder so `/second-brain-ingest` can process it exactly like web-clipped articles.
This skill only writes `raw/` files and its own state — it never ingests, and it never touches `wiki/`.

What syncs by default (high-signal scope):

- **Highlight digests** — one file per highlighted book/article (`<slug>-highlights-<bookid>.md`), regenerated whole whenever that source gains or changes highlights.
- **Read Reader docs** — documents in the `archive` and `later` locations (`<slug>-<id8>.md`), with the Reader AI summary in `description:` and the full markdown content as the body.

What does not sync: the RSS `feed` location (never), and the unread inbox (`new`) unless `--include-inbox` is passed.

## Prerequisites

- `readwise` CLI installed and authenticated — see the `readwise-cli` skill (`npm install -g @readwise/cli`, `readwise login-with-token <token>`).
- A second-brain vault with `raw/` and `wiki/log.md` (default `~/Documents/sanket-wiki`).

## Run the Sync

```bash
python3 {baseDir}/scripts/sync.py
```

Incremental by default: two durable cursors (reader docs, highlights) mean only changes since the last run are fetched.

| Flag | Effect |
|---|---|
| `--vault PATH` | Vault location (default `$READWISE_SYNC_VAULT`, else `~/Documents/sanket-wiki`) |
| `--full` | Ignore cursors and re-fetch everything (still idempotent — unchanged files are skipped by hash) |
| `--include-inbox` | Also sync unread inbox docs (location `new`) |
| `--dry-run` | Fetch, render, and report without writing any file or state |
| `--limit N` | Cap docs and highlight-books processed (for testing) |
| `--docs-only` / `--highlights-only` | Sync a single stream |
| `--state-dir PATH` | Override state location (also `$READWISE_SYNC_STATE_DIR`) |

## Interpret the Report

- **NEW** — files never ingested; `/second-brain-ingest` will auto-detect them.
- **UPDATED** — files previously ingested whose raw content changed (new highlights, edited article); ingest skips these unless named, so pass the listed filenames explicitly.
- **UNCHANGED** — rendered content identical to last sync; nothing written.
- **Pending re-ingest carried** — UPDATED files from earlier runs that still have no newer ingest entry in `wiki/log.md`; the entry clears itself once the file is re-ingested.

## Hand Off

After a sync with NEW or UPDATED files, run `/second-brain-ingest`:

- NEW files are detected automatically (batch mode handles many at once).
- UPDATED files must be named explicitly, e.g. "re-ingest raw/some-article-01jxyz.md (3 new highlights)".

## State and Config

State lives at `~/.local/state/readwise-second-brain-sync/state.json`: the two cursors, a per-document and per-book file registry (filenames are minted once and reused even if titles change), content hashes, and the pending re-ingest ledger.
Delete the state file and run `--full` for a clean rebuild — existing raw files with unchanged content survive untouched thanks to hash gating.

## Troubleshooting

- **Auth expired** — any CLI call failing with an auth error: re-run `readwise login-with-token <token>` (token from https://readwise.io/access_token).
- **One stream failed** — the other stream still completes; the failed stream's cursor is NOT advanced, so the next run re-fetches from the same point.
  Exit code is non-zero in that case.
- **A file reports UNCHANGED but looks stale** — hashes exclude only the volatile `created`/`updated` dates; run `--full --dry-run` to verify what would change.

## Related Skills

- `readwise-cli` — the CLI this skill drives
- `/second-brain-ingest` — processes the synced files into wiki pages
- `/second-brain-lint` — health-checks the wiki afterwards
