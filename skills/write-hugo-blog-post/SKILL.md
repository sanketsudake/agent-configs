---
name: write-hugo-blog-post
description: Use when authoring or editing a blog post in a Hugo site (commonly Docsy) — triggers "write a blog post", "publish a tutorial", "add a post". Covers file layout (single file vs page bundle), front matter, the featured-image to card+OG flow, and the Docsy single-post layout trap.
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

That single param drives **both** the blog-list card thumbnail **and** the OG/social preview image.
No featured image is fine — cards fall back to a site-defined placeholder.
Do not also embed the featured image at the top of the post body; the card already shows it.

## Body Conventions

- One sentence per line if the project uses that Markdown style (CommonMark renders single newlines as spaces; diffs become per-sentence).
- Code fences with language hints; real, runnable commands with expected output.
- Use your project's version shortcodes for version strings — a hardcoded version goes stale silently.
- Internal links as absolute paths (`/docs/usage/…`); avoid `{{< relref >}}` unless your project uses it for regular pages (Docsy's relref shortcode only resolves section `_index.md` paths).
- Images get descriptive alt text; lightbox (click-to-zoom) typically wires up automatically.
- Use your project's category set, version shortcodes, and link conventions; see the project's content conventions.

## The Docsy Single-Post Layout Trap

In Docsy, the file that actually renders a blog post is `layouts/blog/_td-content.html`.
A `layouts/blog/content.html` override is **dead code** — it is never called.
If you need to customize a post's layout, edit `_td-content.html`.

## Verify

```bash
hugo server
```

Check:
- `/blog/` — card shows the thumbnail (not the fallback), correct date/author/reading time/category pill, sensible excerpt.
- `/blog/<slug>/` — byline renders, images load, code blocks highlight.
- Run `./build.sh` (or `hugo --minify --printPathWarnings --gc`) to catch bad front matter and broken refs; see the `verify-hugo-docsy-build` skill.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| `images` path typo or file not under `static/` | Card shows fallback thumbnail unexpectedly | Path is relative to `static/`; check the filename |
| Edited `layouts/blog/content.html` for layout tweaks | Nothing changes | Dead file — Docsy renders `layouts/blog/_td-content.html` |
| Added "5 min read" or a byline manually | Duplicated meta on the post | Both are automatic from the layout |
| New category invented | Lonely taxonomy page with one post | Reuse an existing category |
| Date without timezone or set in the future | Post sorts oddly or does not appear | Use ISO-8601 with TZ offset and a current time |
