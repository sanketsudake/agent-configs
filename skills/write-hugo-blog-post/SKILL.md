---
name: write-hugo-blog-post
description: Use when authoring or editing a blog post in a Hugo site (any theme) — triggers "write a blog post", "publish a tutorial", "add a post". Covers file layout (single file vs page bundle), front matter, the featured-image to card+OG flow, and the layout that actually renders a post.
---

# Writing a Hugo Blog Post

## Overview

Posts live under the site's `content/blog/` (or equivalent) directory and publish at `/blog/<slug>/`.
The list page renders each post as a card: thumbnail, title, date · author · reading time, category pill, excerpt.
Byline and reading time are automatic from the layout — never add them by hand.

## File Layout

- **Single file** (text-only): `content/blog/my-post-slug.md` (or `content/<lang>/blog/…` on a multilingual site).
- **Page bundle** (post with its own images): `content/blog/my-post-slug/index.md` plus images next to it, referenced relatively (`![alt](diagram.png)`).
- Sitewide images (featured, shared logos) go in `static/images/` and are referenced as `/images/…`.

## Front Matter

```toml
+++
title = "Your Post Title Here"
date = "2026-01-15T10:00:00+05:30"
author = "Full Name"
categories = ["<your-category>"]
description = "One-sentence summary used in cards, RSS, and OG tags."
type = "blog"
images = ["images/featured/my-post-featured.png"]
+++
```

- `type = "blog"` is required for the layout to activate.
- `description` is required — it is the meta description, OG description, and any LLM/search-index entry.
- `author` full name; links to the author taxonomy page automatically.
- `date` must be ISO-8601 with timezone offset; the list groups by year and sorts by it.
- Use your project's category set — do not invent new categories that create lonely taxonomy pages.

## Featured Image

1. Create a PNG around **1000×563** (16:9-ish), named `<slug>-featured.png`.
2. Place it in `static/images/featured/`.
3. Reference it in the `images` front-matter field (path relative to `static/`, leading slash optional).

That single param drives **both** the blog-list card thumbnail **and** the OG/social preview image; omitting it falls back to a site-defined placeholder.
Do not also embed the featured image at the top of the post body; the card already shows it.

## Body Conventions

- One sentence per line if the project uses that Markdown style (CommonMark renders single newlines as spaces; diffs become per-sentence).
- Code fences with language hints; real, runnable commands with expected output.
- Use your project's version shortcodes for version strings — a hardcoded version goes stale silently.
- Internal links as absolute paths (`/docs/usage/…`); use `{{< relref >}}` only if your project/theme supports it for regular pages — some themes restrict it to section `_index.md` paths.
- Images get descriptive alt text; lightbox (click-to-zoom) typically wires up automatically.

## Find the layout that actually renders a post

Themes often ship more than one candidate layout for a single page; only one is actually used, and editing the wrong (dead) one changes nothing.
Before customizing a post's layout, confirm which template Hugo selects (build with `--printPathWarnings`, or check the theme's lookup order) and edit that file.

## Verify

```bash
hugo server
```

Check:
- `/blog/` — card shows the thumbnail (not the fallback), correct date/author/reading time/category pill, sensible excerpt.
- `/blog/<slug>/` — byline renders, images load, code blocks highlight.

Then use the `verify-hugo-build` skill to validate the full build (catches bad front matter and broken refs).

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| `images` path typo or file not under `static/` | Card shows fallback thumbnail unexpectedly | Path is relative to `static/`; check the filename |
| Edited a layout candidate that is not the selected template | Nothing changes | Confirm the selected template (`--printPathWarnings`) and edit that file |
| Added "5 min read" or a byline manually | Duplicated meta on the post | Both are automatic from the layout |
| New category invented | Lonely taxonomy page with one post | Reuse an existing category |
| Date without timezone or set in the future | Post sorts oddly or does not appear | Use ISO-8601 with TZ offset and a current time |
