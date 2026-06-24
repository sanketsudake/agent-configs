---
name: generate-og-images
description: Use to generate branded 1200x630 social-share (OG/Twitter) card images for a site's pages, with title/tags/brand overlaid by Pillow over an AI, image, or gradient background. Triggers "make an OG image", "social card", "regenerate the share image". Generic to any Hugo-style content tree.
---

# Generate social-share (OG) card images

Run when adding a post/talk, after changing a page's title or tags, or to generate the site-wide default card.

## Workflow

```bash
python3 <skill-dir>/gen-og-image.py \
  --brand my.site --author "Full Name" \
  --subtitle "Topic A · Topic B" \
  --sections posts,talks \
  path/to/content/<slug>/index.md
```

- Targets are markdown files or bundle dirs; or `--all-content`; or `--default` for the site card.
- `--brand` / `--author` / `--subtitle` overlay text (no defaults — pass them).
- `--bg FILE` / `--bg-dir DIR` supply backgrounds; `--print-prompts` emits per-item AI prompts to paste into an image tool; absent → gradient.
- `GEMINI_API_KEY` (paid tier) enables AI backgrounds.

## Guardrails

- Output is a 1200×630 PNG; place it where the site's OG templates resolve it (bundle `feature.png`, or `static/og/...`).
- Don't embed the card in the page body — it's a social asset only.

## Output

One PNG per target.
