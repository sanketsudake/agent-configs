# Wiki Schema

Canonical rules for LLM-maintained knowledge base wikis.
This is the single source of truth — agent config templates pull from this document.

After editing this file, re-sync any live vault agent config (e.g. the vault's `CLAUDE.md`) by replacing everything from `## Architecture` onward with this file's content from `## Architecture` onward.

## Architecture

Three directories, three roles:

- **raw/** — immutable source documents.
  The LLM reads from here but NEVER modifies these files.
- **wiki/** — the LLM's workspace.
  Create, update, and maintain all files here.
- **output/** — reports, query results, and generated artifacts go here.

Wiki subdirectories:
- `wiki/sources/` — one summary page per ingested source
- `wiki/entities/` — pages for people, organizations, products, tools
- `wiki/concepts/` — pages for ideas, frameworks, theories, patterns
- `wiki/synthesis/` — comparisons, analyses, cross-cutting themes

Two special files:
- `wiki/index.md` — master catalog of every wiki page, organized by category.
  Update on every ingest.
- `wiki/log.md` — append-only chronological record.
  Never edit existing entries.

## Page Format

Every wiki page MUST include YAML frontmatter:

    ---
    tags: [tag1, tag2]
    sources: [source-filename-1.md, source-filename-2.md]
    created: YYYY-MM-DD
    updated: YYYY-MM-DD
    ---

Source pages carry two additional optional fields: `ingest: light | deep` (absence means deep, for legacy pages) and `source_url: https://...`.

Use `[[wikilink]]` syntax for all internal links.
When you mention a concept, entity, or source that has its own page, link it.

## Operations

### Ingest (processing a new source)

Ingestion has two tiers.

**Deep** — for a single interactive source, or one flagged `deep: true` / tagged `deep-ingest` / explicitly named by the user:

1. Read the source completely
2. Discuss key takeaways with the user (interactive invocations only; skipped in batch runs)
3. Create a source summary page in `wiki/sources/` with: title, source metadata, key claims, and a structured summary
4. Identify all entities and concepts mentioned.
   For each:
   - If a wiki page exists: update it with new information from this source, noting the source
   - If no wiki page exists: create one in the appropriate subdirectory
5. Add `[[wikilinks]]` between all related pages
6. Update `wiki/index.md` with any new pages
7. Append to `wiki/log.md`: `## [YYYY-MM-DD] ingest | Source Title`

A single deep source may touch 10-15 wiki pages.
That is normal.

**Light** — the default for every file in a batch run:

1. Read the source frontmatter and skim the body; the `description` summary and any highlights are the payload
2. Create a source summary page marked `ingest: light` carrying the summary and verbatim highlights
3. Create or update NO entity or concept pages; inline wikilinks only to pages that already exist
4. Update `wiki/index.md`; one `batch-ingest` log entry covers the whole batch
5. Report at batch end (counts, deep candidates ranked by highlights, junk authors sanitized) instead of per-source confirmation

### Deepen (upgrading a light page)

When the user asks to deepen a page, or accepts a lint/batch suggestion:

1. Re-read the page's raw source completely
2. Rewrite the source page in full deep form, keeping the original `created:` date
3. Run the deep entity/concept steps
4. Set `ingest: deep`, bump `updated:`
5. Log a `deepen` entry without a new `Processed:` filename line

### Query (answering questions)

When the user asks a question:

1. Read `wiki/index.md` to find relevant pages
2. Read the relevant wiki pages
3. Synthesize an answer with `[[wikilink]]` citations to wiki pages
4. If the answer produces a valuable artifact (comparison, analysis, new connection), offer to save it as a new page in `wiki/synthesis/`
5. If you save a new page, update the index and log

### Lint (health check)

When the user asks you to lint or health-check the wiki:

1. Scan for contradictions between pages
2. Find stale claims that newer sources have superseded
3. Identify orphan pages (no inbound links)
4. Find important concepts mentioned but lacking their own page
5. Check for missing cross-references
6. Suggest data gaps that could be filled with a web search
7. Report findings and offer to fix issues
8. Log the lint pass: `## [YYYY-MM-DD] lint | Summary of findings`

## Index Format

Each entry in `wiki/index.md` is one line:

    - [[Page Name]] — one-line summary

Organized under category headers: Sources, Entities, Concepts, Synthesis.

`index.md` stays a single flat file; shard into per-category files only if the Sources section passes ~150 entries or the file passes ~500 lines.
When sharded, the moved section lives in a sibling catalog (e.g. `wiki/index-sources.md`) and `index.md` keeps a one-line pointer to it; ingest then updates the sharded file.

## Log Format

Each entry in `wiki/log.md`:

    ## [YYYY-MM-DD] operation | Title
    Brief description of what was done.

Ingest-family entries record every processed raw filename exactly, backticked, on a `Processed:` line — this is the contract unprocessed-detection and external sync tools grep for.

    ## [YYYY-MM-DD] batch-ingest | Batch label (N light, M deep)
    Processed: `file-one.md` -> [[Page One]] (light)
    Processed: `file-two.md` -> [[Page Two]] (deep: 3 new entities)
    Deep candidates: [[Page One]] (14 highlights)

    ## [YYYY-MM-DD] deepen | Page Title
    Promoted [[Page Title]] to deep: N new entities, M new concepts.

## Page Naming

Filenames use **kebab-case** with `.md` extension.
Page titles inside the file use **Title Case**.

- Source pages: `wiki/sources/article-title-here.md` → `# Article Title Here`
- Entity pages: `wiki/entities/entity-name.md` → `# Entity Name`
- Concept pages: `wiki/concepts/concept-name.md` → `# Concept Name`
- Synthesis pages: `wiki/synthesis/comparison-topic.md` → `# Comparison Topic`

When creating `[[wikilinks]]`, use the page title (Title Case), not the filename:
- Correct: `[[Entity Name]]`
- Wrong: `[[entity-name]]`

To slugify a title into a filename: lowercase, replace spaces with hyphens, remove special characters, trim to reasonable length.

## Image Handling

Web-clipped articles often include images.
Handle them as follows:

1. **Download images locally.**
   In Obsidian Settings → Files and links, set "Attachment folder path" to `raw/assets/`.
   Then use "Download attachments for current file" (bind it to a hotkey like Ctrl+Shift+D) after clipping an article.
2. **Reference images from wiki pages** using standard markdown: `![description](../raw/assets/image-name.png)`.
   Keep the image in `raw/assets/` — never copy images into `wiki/`.
3. **During ingestion**, note any images in the source.
   If an image contains important information (diagrams, charts, data), describe its contents in the wiki page so the knowledge is captured in text form.

## Lint Frequency

Run lint (`/second-brain-lint`) in two modes:
- **Quick lint — automatically at the end of every batch ingest** — broken wikilinks, index consistency, junk-entity scan, log↔raw detection round-trip
- **Full lint — monthly, on demand, or before any major query or synthesis** — everything, including contradictions, stale claims, and deepen candidates

## Tools

You have access to these CLI tools — use them when appropriate:

- **summarize** — summarize links, files, and media.
  Run `summarize --help` for usage.
- **qmd** — local search engine for markdown files.
  Run `qmd --help` for usage.
  Use when the wiki grows beyond what index.md can efficiently navigate.
- **agent-browser** — browser automation for web research.
  Use when web_search or web_fetch fail.

## Rules

1. Never modify files in `raw/`.
   They are immutable source material.
2. Always update `wiki/index.md` when you create or delete a page.
3. Always append to `wiki/log.md` when you perform an operation.
4. Use `[[wikilinks]]` for all internal references.
   Never use raw file paths in page content.
5. Every wiki page must have YAML frontmatter with tags, sources, created, and updated fields.
6. When new information contradicts existing wiki content, update the wiki page and note the contradiction with both sources cited.
7. Keep source summary pages factual.
   Save interpretation and synthesis for concept and synthesis pages.
8. When asked a question, search the wiki first.
   Only go to raw sources if the wiki doesn't have the answer.
9. Prefer updating existing pages over creating new ones.
   Only create a new page when the topic is distinct enough to warrant it.
10. Keep `wiki/index.md` concise — one line per page, under 120 characters per entry.
11. Before wikilinking an author or creating an entity page from one, require a name-like value: reject all-digits ids, domain-like strings, values over 60 characters, or letterless handles — write those as plain text instead.
12. Light source pages (`ingest: light`) are upgraded only via the Deepen operation — never hand-edit one into pseudo-deep form.
