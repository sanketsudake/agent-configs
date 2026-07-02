---
name: second-brain-review
description: >
  Resurface knowledge from the second-brain wiki — a daily/periodic review of
  highlights, concepts, and stale pages, replacing Readwise's daily review.
  Use when the user says "daily review", "review my highlights", "resurface
  something", "what should I revisit", or wants spaced-repetition-style
  engagement with their wiki.
allowed-tools: Bash Read Write Edit Glob Grep
---

# Second Brain — Review

Resurface a small, rotating set of the user's own knowledge: highlights they made, concepts the wiki holds, and pages going stale.
This is the wiki-native replacement for Readwise's daily review.

## Pick the Set

```bash
python3 {baseDir}/scripts/pick-review.py
```

Returns JSON: ~7 items (60% highlights, 30% concepts, the rest oldest-updated source pages), seeded by today's date (same-day re-runs match), excluding anything reviewed in the last 30 days.
Flags: `--count N`, `--vault PATH`, `--exclude-days N`, `--seed X`.

## Present the Review

Show each item conversationally, one small block per item — not a data dump:

- **Highlight** → quote it, name the source: *"You highlighted this in [[Page]]: …"*, and add one line of why it might matter now (connect to another wiki page when a real link exists).
- **Concept** → state the concept in one or two sentences from its page and ask a light recall prompt: *"How would you explain [[Concept]] in your own words?"* — the user can engage or skip.
- **Stale source** → *"[[Page]] hasn't been touched since <date> — still relevant, or archive-worthy?"*

Keep the whole review scannable in under a minute.
Do not lecture; the user's engagement is optional per item.

## Capture What the Review Produces

Reviews compound only if their output lands back in the wiki:

- User draws a connection between items → offer to save it as a `wiki/synthesis/` page (frontmatter + `[[wikilinks]]`, index + log per schema).
- User wants more on a light source → hand off to `/second-brain-ingest` deepen.
- User says a stale page is obsolete → note the candidate for the next `/second-brain-lint` pass rather than deleting inline.

## Log the Review

Append one entry (append-only):

```
## [YYYY-MM-DD] review | Daily review
Reviewed: [[Page One]], [[Page Two]], [[Concept X]], ... Saved: [[Synthesis Page]] (if any).
```

The `Reviewed:` wikilinks are what `pick-review.py` reads to avoid repeats within the exclusion window — always list every presented page.

## Scheduling (optional)

The skill is single-shot by design.
For a recurring cadence, schedule it externally — e.g. a daily `/schedule` routine or cron invoking `/second-brain-review` — rather than looping inside the skill.

## Related Skills

- `/second-brain-query` — dig into anything the review surfaces
- `/second-brain-ingest` — deepen a source the review flags
- `/second-brain-lint` — full health pass; consumes stale/obsolete notes from reviews
