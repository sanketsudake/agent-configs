---
name: optimize-svg
description: Use when adding or committing an SVG asset (logos, icons) to keep it small — triggers "add this logo", "optimize svg", "svg is too big". Runs svgo and keeps the result only if it actually shrank.
---

# Optimizing SVG Assets

## Overview

Run `svgo` before committing any SVG.
Accept the result only if it is smaller — svgo sometimes inflates already-optimized files.

## Steps

```bash
npx svgo --multipass <file.svg>
```

- If the file shrank: keep it.
- If the file grew or stayed the same: `git checkout -- <file.svg>` (revert).

## Size Guidance

- Flag any SVG over **~10 KB** for review — it may be an illustration that can be replaced with a simpler mark.
- Prefer the minimal official mark over a heavy illustration.
A 0.7 KB icon is almost always better than a 52 KB marketing illustration for a site asset.
- If a single SVG exceeds 10 KB after `svgo --multipass`, consider whether it should be split, rasterized (PNG/WebP), or replaced with a simpler version.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Committed svgo output without checking size | File is larger than the original | Always compare before/after size; revert if bigger |
| Used single-pass svgo | Suboptimal compression | Use `--multipass` |
| Added a 50+ KB illustration as a site asset | Slow page load, large repo | Replace with a lightweight icon or rasterize |
