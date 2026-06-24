---
name: add-llms-txt
description: Use to add LLM-friendly outputs to a Hugo site — /llms.txt and /llms-full.txt indexes plus a per-page markdown twin at <url>/index.md — generated from content so they stay in sync. Triggers "add llms.txt", "make the site agent-friendly", "markdown twin".
---

# Add llms.txt + markdown twins to a Hugo site

Never hand-edit `public/` — these outputs are generated from content.

## Workflow

1. Add the output formats + assignments to the site config (paste the verbatim block from this skill — copied from a working site):

   ```toml
   [outputs]
     home = ["HTML", "RSS", "JSON", "llms", "llmsfull"]
     # Every content page also emits a clean markdown twin at <url>/index.md for
     # LLMs/agents that fetch a single page (rendered by layouts/_default/single.markdown.md).
     page = ["HTML", "markdown"]

   # Dedicated media type so both LLM output formats render with a .txt extension
   # (markdown's own media type would force .md). The two output formats share it,
   # differentiated by baseName.
   [mediaTypes]
     [mediaTypes."text/llms"]
       suffixes = ["txt"]
       delimiter = "."

   [outputFormats]
     [outputFormats.llms]
       mediaType = "text/llms"
       baseName = "llms"
       isPlainText = true       # do not HTML-escape the markdown body
       rel = "alternate"        # head.html auto-emits a <link rel="alternate"> for it
     [outputFormats.llmsfull]
       mediaType = "text/llms"
       baseName = "llms-full"
       isPlainText = true
       rel = "alternate"
     # Per-page markdown twin. Uses Hugo's built-in text/markdown media type (.md);
     # baseName "index" yields <page-dir>/index.md. rel="alternate" makes head.html
     # advertise it on each page.
     [outputFormats.markdown]
       mediaType = "text/markdown"
       baseName = "index"
       isPlainText = true
       rel = "alternate"
   ```

2. Copy the templates from this skill dir into the site's `layouts/`:
   - `index.llms.txt` → `layouts/index.llms.txt`
   - `index.llmsfull.txt` → `layouts/index.llmsfull.txt`
   - `single.markdown.md` → `layouts/_default/single.markdown.md`

Adjust section names (`"posts"`, `"talks"`) to the target site's content sections.
If the site has no canonical-URL field, the `canonicalURL` references are no-ops (`.Params.canonicalURL` returns empty string).

3. Customize `index.llms.txt` for the target site:
   - Set `params.llmsIntro` in `hugo.toml`/`params.toml` to a one-sentence site description for LLM crawlers — e.g. `llmsIntro = "Technical writing on Kubernetes and platform engineering."`.
     If unset, the template falls back to `"Content by <author.name>."`.
   - Set `params.author.bio` for the About line, or edit the About section directly.

4. Advertise the twin: ensure the head partial emits `<link rel="alternate" type="text/markdown" href="index.md">`.
   Congo does this automatically when `rel = "alternate"` is set on the output format.

## Guardrails

- These outputs are generated — regenerate by rebuilding; never edit `public/`.
- Allow AI crawlers in `robots.txt` if you want them fetched (GPTBot, ClaudeBot, PerplexityBot, Google-Extended, etc.).
- The `llms-full.txt` template only iterates `"posts"` — if the target site uses a different section name, update the range filter.

## Output

`/llms.txt`, `/llms-full.txt`, and per-page `index.md` twins, all build-generated.
