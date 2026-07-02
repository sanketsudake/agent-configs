---
name: second-brain-ingest
description: >
  Process raw source documents into wiki pages. Use when the user adds
  files to raw/ and wants them ingested, says "process this source",
  "ingest this article", "batch ingest", "deepen", "I added something
  to raw/", or wants to incorporate new material into their knowledge base.
allowed-tools: Bash Read Write Edit Glob Grep
---

# Second Brain — Ingest

Process raw source documents into structured, interlinked wiki pages.
Two tiers exist: **light** (fast, batch-safe source page) and **deep** (full entity/concept extraction).

## Identify Sources to Process

Determine which files need ingestion:

1. If the user specifies a file or files, use those.
2. If the user says "process new sources" or similar, detect unprocessed files mechanically:

```bash
# All raw sources
ls raw/*.md
# All filenames already recorded in the log (backticked new-style, double-quoted legacy-style)
grep -ohE '`[^`]+\.md`|"[^"]+\.md"' wiki/log.md | tr -d '`"' | sort -u
```

The set difference (raw files absent from the log output) is the unprocessed set.
3. If no unprocessed files are found, tell the user.

A raw file counts as ingested iff its exact filename appears in `wiki/log.md` backticked on a `Processed:` line (new style) or double-quoted (legacy style).
Always record filenames exactly in that form when logging — other tools (e.g. the `readwise-second-brain-sync` skill) parse the same contract.

## Choose the Tier

Decide per file, without asking the user:

| Condition | Tier |
|---|---|
| User explicitly names the file, or says "deep ingest X" / "deepen X" | deep |
| Raw frontmatter contains `deep: true` or the tag `deep-ingest` | deep |
| Single-source interactive invocation ("ingest this article") | deep (with the takeaway discussion below) |
| Anything else in a batch run | light |

A light-tier file that carries highlights (a `## Highlights` section or highlight blockquotes in the body) stays light but is recorded as a **deep candidate** in the batch report.
Highlights promote a file to candidate, never to automatic deep processing.

Re-ingesting a file that was already processed (e.g. named explicitly because its raw content was updated) redoes its **existing tier** — read the current source page's `ingest:` frontmatter — unless the user asks to deepen.

## Author Sanitation (both tiers)

Before treating an author value as an entity or wikilinking it, require it to look like a person or organization name.
Reject the value if it is all digits, looks like a domain or URL (contains a `.` with no spaces, or matches the source URL host), is longer than 60 characters, or contains no letters.
Rejected values are written as plain text with any `[[ ]]` brackets stripped — never wikilinked, never given an entity page.
Example that must be caught: `author: - "[[262588213843476]]"`.

## Batch Mode (light ingest loop)

Use for multi-file runs.
Skip the takeaway discussion entirely — the end-of-batch report replaces per-source confirmation.

For each file:

1. Read the raw frontmatter and skim the body.
   The frontmatter `description` (AI summary) and any highlights are the payload; do not deep-read the full text.
2. Write a lightweight source page to `wiki/sources/<slug>.md`:

```markdown
---
tags: [reading, <domain-tags-from-source-frontmatter>]
sources: [<exact raw filename>.md]
source_url: https://...
created: YYYY-MM-DD
updated: YYYY-MM-DD
ingest: light
---

# Source Title

**Source:** <exact raw filename>.md
**Author:** Plain Author Name
**Published:** YYYY-MM-DD
**Date ingested:** YYYY-MM-DD
**Type:** article | highlights-digest | paper | notes

## Summary

<the frontmatter description, lightly cleaned — no new analysis>

## Highlights

- verbatim highlight 1
- verbatim highlight 2

## Upgrade Notes

Light ingest — no entity/concept extraction performed. Run `/second-brain-ingest deepen` to promote.
```

Omit the Highlights section when the source has none.
Wikilink the author only if it passes the sanitation heuristic AND its entity page already exists.
3. **Create or update zero entity and concept pages.**
   Inline `[[wikilinks]]` in the Summary are allowed only for pages that already exist — check with `qmd search "<topic>" --path wiki/` (fallback: `grep -ril "<topic>" wiki/entities wiki/concepts`), or skip inline links entirely; lint's cross-reference pass adds them later.
4. Add one line to `wiki/index.md` under Sources.
5. Accumulate results; do not log per file.

After the loop, append ONE log entry:

```
## [YYYY-MM-DD] batch-ingest | <batch label> (N light, M deep)
Processed: `some-article.md` -> [[Some Article]] (light)
Processed: `other-doc.md` -> [[Other Doc]] (light, 14 highlights)
Processed: `flagged-paper.md` -> [[Flagged Paper]] (deep: 3 new entities, 2 new concepts)
Deep candidates: [[Other Doc]] (14 highlights), [[Third Doc]] (9 highlights)
```

One backticked filename per `Processed:` line — this is what unprocessed-detection greps for.

Then report to the user:

```
Batch ingest complete: 12 sources (11 light, 1 deep), 0 skipped, 0 failed.
- New source pages: [[...]] x12
- Deep candidates (by highlight count): [[Other Doc]] (14), [[Third Doc]] (9)
- Junk authors sanitized: 262588213843476, dev.to
- Suggested next: /second-brain-ingest deepen "Other Doc"
```

Finally, run the quick-lint checks from `/second-brain-lint` (broken wikilinks, index consistency, junk-entity scan, detection round-trip) and `qmd update` if qmd is installed.

## Deep Ingest (single source or flagged file)

### 1. Read the source completely

Read the entire file.
If the file contains image references, note them — read the images separately if they contain important information.

### 2. Discuss key takeaways with the user (interactive mode only)

In an interactive single-source invocation, share the 3-5 most important takeaways, ask what to emphasize or skip, and wait for confirmation.
In batch mode this step is SKIPPED — deep-tier files inside a batch go straight through, and the batch report replaces confirmation.

### 3. Create source summary page

Create a new file in `wiki/sources/` named after the source (slugified).
Include:

    ---
    tags: [relevant, tags]
    sources: [original-filename.md]
    source_url: https://...
    created: YYYY-MM-DD
    updated: YYYY-MM-DD
    ingest: deep
    ---

    # Source Title

    **Source:** original-filename.md
    **Date ingested:** YYYY-MM-DD
    **Type:** article | paper | transcript | notes | etc.

    ## Summary

    Structured summary of the source content.

    ## Key Claims

    - Claim 1
    - Claim 2

    ## Entities Mentioned

    - [[Entity Name]] — brief context

    ## Concepts Covered

    - [[Concept Name]] — brief context

### 4. Update entity and concept pages

For each entity (person, organization, product, tool) and concept (idea, framework, theory, pattern) mentioned in the source:

Before creating, check whether a page already exists: `qmd search "Entity Name" --path wiki/` (fallback: `Glob wiki/entities/<slug>*.md` plus `grep -ril "entity name" wiki/entities wiki/concepts`).

**If a wiki page already exists:**
- Read the existing page
- Add new information from this source
- Add the source to the `sources:` frontmatter list
- Update the `updated:` date
- Note any contradictions with existing content, citing both sources

**If no wiki page exists:**
- Create a new page in the appropriate subdirectory:
  - `wiki/entities/` for people, organizations, products, tools
  - `wiki/concepts/` for ideas, frameworks, theories, patterns
- Include YAML frontmatter with tags, sources, created, and updated fields
- Write a focused summary based on what this source says about the topic

Author values must pass the sanitation heuristic before getting an entity page.

### 5. Add wikilinks

Ensure all related pages link to each other using `[[wikilink]]` syntax.
Every mention of an entity or concept that has its own page should be linked.

### 6. Update wiki/index.md

For each new page created, add an entry under the appropriate category header:

    - [[Page Name]] — one-line summary (under 120 characters)

### 7. Update wiki/log.md

Append (single interactive ingest):

    ## [YYYY-MM-DD] ingest | Source Title
    Processed: `source-filename.md` -> [[Source Title]] (deep: N new pages, M updated)
    New entities: [[Entity1]], [[Entity2]]. New concepts: [[Concept1]].

### 8. Report results

Tell the user what was done:
- Pages created (with links)
- Pages updated (with what changed)
- New entities and concepts identified
- Any contradictions found with existing content

## Process Local Highlights (==marks== made while reading in the vault)

Trigger: the user says "process my highlights", "I highlighted some things", or a batch run finds marked files.
These are `==highlight==` marks the user added while reading raw files in Obsidian — the one permitted human edit to `raw/`.

1. Find candidates: `grep -lE '==[^=]' raw/*.md`.
   Skip matches that sit inside code fences — `==` also appears in code.
2. For each candidate, extract every `==...==` span and diff against the source page's existing `## Highlights` bullets.
3. Append only the missing spans, verbatim, as bullets (create the section above `## Upgrade Notes` if absent); bump `updated:`.
4. A source that gains local highlights becomes a **deep candidate**, same as one arriving with Readwise highlights.
5. Log once per pass, without `Processed:` lines (the files are already ingested):

```
## [YYYY-MM-DD] highlights | N passages from M sources
Updated: [[Page One]] (+2), [[Page Two]] (+1). Deep candidates: [[Page One]].
```

## Deepen (upgrade a light page)

Trigger: the user asks (`deepen <page or raw file>`), or accepts a deep-candidate suggestion from a batch report or lint pass.

1. Resolve the source page; read its `sources:` frontmatter entry; read that raw file completely.
2. Run deep steps 3-6: rewrite the source page in full deep form (keep the original `created:` date), then entity/concept pages with dedup, wikilinks, and index updates.
   The author heuristic still applies.
3. Set `ingest: deep`, bump `updated:`.
4. Log:

```
## [YYYY-MM-DD] deepen | Page Title
Promoted [[Page Title]] to deep: N new entities, M new concepts.
```

Do NOT add another `Processed:` backticked-filename line — the file is already accounted for, and a duplicate would not break detection but adds noise.

## Conventions

- Source summary pages are **factual only**.
  Save interpretation and synthesis for concept and synthesis pages.
- Light is the batch default; a light source touches exactly 2 files (its page + the index).
- A deep source typically touches **10-15 wiki pages**.
  This is normal and expected — for the deep tier only.
- When new information contradicts existing wiki content, **update the wiki page and note the contradiction** with both sources cited.
- **Prefer updating existing pages** over creating new ones.
  Only create a new page when the topic is distinct enough to warrant its own page.
- Never create entity pages from author fields that fail the name heuristic.
- Use `[[wikilinks]]` for all internal references.
  Never use raw file paths.

## What's Next

After ingesting sources, the user can:
- **Ask questions** with `/second-brain-query` to explore what was ingested
- **Read in the vault** and mark passages with `==highlight==` — then "process my highlights" lifts them into the wiki
- **Deepen** high-value light pages — the batch report and lint rank candidates
- **Ingest more sources** — clip or sync another source and run `/second-brain-ingest` again
- **Health-check** with `/second-brain-lint` — quick-lint runs automatically after each batch; run a full lint monthly
