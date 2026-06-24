---
name: verify-hugo-build
description: Use when verifying a Hugo site build before declaring it done or pushing (triggers "does it build", "verify the site", after editing layouts/SCSS/content). Builds the way the host runs it and explains why hugo --gc --quiet is not enough.
---

# Verify a Hugo Build

Running the same build command the deploy host runs is the only reliable local verification: `hugo --gc --quiet` skips `--minify`, which is what exercises the PostCSS pipeline — a build that passes `--gc --quiet` can still fail in production.

## Build doctrine

Run the production build, not a shortcut:

```bash
# If the repo has a build script, use it — it wraps the canonical flags:
./build.sh

# If not, run the equivalent directly:
hugo --minify --printPathWarnings --gc
```

**Use the Hugo version the deploy config pins**, not a system or Homebrew Hugo.
Find it in the deploy config (e.g. `HUGO_VERSION` in `netlify.toml`).
Hugo 0.158+ wraps the PostCSS pipeline in Node's experimental Permission Model with a restricted filesystem scope, which breaks browserslist's parent-directory search and can hang or fail `hugo --minify` — if the theme records a tested Hugo version, pin to it.

## Reading the output

Any `ERROR` is a hard build failure.
A `WARN` (e.g. a missing partial or shortcode) is a soft failure — investigate before pushing.
A clean build prints the full page table untruncated and the page count rises as expected (+1 for a new page, +N for a new section).

## When to also browser-verify

After editing **layouts or SCSS**, start `hugo server` and load the affected pages in a browser.
A build-clean flag does not catch visual regressions.
Use the `browser-tools` skill to automate browser interaction if needed.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Used `hugo --gc --quiet` | "Clean locally" but deploy fails | Run `hugo --minify --printPathWarnings --gc` (or `./build.sh`) |
| Used Homebrew or system Hugo | `hugo --minify` hangs or errors (`ERR_ACCESS_DENIED`) | Pin to the version in the deploy config |
| Used Hugo non-extended build | SCSS/asset pipeline breaks | Themes with an SCSS/asset pipeline require Hugo **extended** |
