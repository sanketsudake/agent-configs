---
name: audit-static-site
description: Use to crawl a built static-site output dir and flag SEO/UX issues (titles, meta descriptions, alt text, thin/orphan/duplicate pages) before publishing. Triggers "audit the site", "SEO check", "check the build for SEO". Generic to any static site whose output is plain HTML.
---

# Audit a built static site

Run after a production build, before publishing — or as a gate in an improvement loop (`--check` exits non-zero on any ERROR).

## Workflow

Run the vendored script against the built output:

```bash
python3 <skill-dir>/site-audit.py \
  --public public \
  --site-suffix " | My Site" \
  --sections posts,talks \
  --out docs/audit/<date>.md
```

- `--public` built output dir (default `public`).
- `--site-suffix` the trailing site-name string appended to every `<title>`, stripped before length checks.
- `--sections` comma-separated content section dirs to audit.
- `--check` exit 1 on any ERROR — use in CI / loops.
- `--min-words` thin-content threshold (default 300).

It flags over/under-length titles & descriptions, missing meta description, images without alt text, thin pages, orphan pages, and duplicate titles/descriptions.

## Guardrails

- Reads the BUILT output, not `content/` — rebuild first.
- Defaults are generic SEO ranges; override per project rather than hardcoding.

## Output

A markdown report grouped by severity (or `--check` for a CI exit code).
