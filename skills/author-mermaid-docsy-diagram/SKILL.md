---
name: author-mermaid-docsy-diagram
description: Use when adding or fixing a mermaid diagram in Docsy/Hugo docs so it renders readably inline in the narrow docs column (triggers "add a diagram", "mermaid", "diagram is too wide/unreadable"). Covers the width rule, layout direction, and the browser viewBox check.
---

# Authoring Mermaid Diagrams in Docsy/Hugo Docs

## Overview

Docsy has native mermaid support — authors write standard ` ```mermaid ` fences.
The critical constraint is the **~900 px width rule**: the docs column is typically ~800 px, so a diagram whose natural (viewBox) width exceeds ~900–950 px shrinks until its text is unreadable inline.

## Width Rule

Keep every diagram under ~900–950 px natural width.

Measure in a browser after `hugo server`:

```js
document.querySelector('.mermaid svg').viewBox.baseVal.width
```

Design choices that keep diagrams narrow:

- Prefer `flowchart TB` (top-to-bottom) over `flowchart LR` (left-to-right).
- ≤3 nodes per rank.
- ≤4-word edge labels.
- ≤12 nodes per diagram — split larger ones.
- Avoid side-by-side subgraphs: the `direction` attribute on a subgraph is **ignored** when its nodes have external edges, so paired subgraphs force a wide layout regardless.

## Diagram Type Choice

| Type | Use for |
|---|---|
| `flowchart TB` | Component/data flows (default) |
| `sequenceDiagram` | Request/interaction ordering between actors |
| `stateDiagram-v2` | Lifecycles (states and transitions) |

For `sequenceDiagram`: use `autonumber`, keep to ≤4 participants, use short participant names.
Avoid `classDiagram` in docs — it rarely fits the width rule and is seldom the right tool for documentation flows.

## Step Numbers on Arrows

Label numbered steps as `-->|"<b>1.</b> description"|` — the `<b>` renders bold via the project's stylesheet.
Never use circled glyphs (①②③).
`sequenceDiagram` uses `autonumber` instead of manual labels.

## Palette

Apply your project's semantic `classDef` kit if it defines one.
Do not embed project-specific colors in diagrams that might be reused across sites.

## Tooling Gotchas

- **Docsy caches partials**: after editing `body-end.html` (or any hook partial), restart `hugo server` — live reload serves the stale partial.
- **Lightbox keeps SVG ids**: the click-to-zoom lightbox clones the SVG and scopes its embedded CSS to the original `id`. Do not strip ids from mermaid output.
- Diagrams must be readable inline without clicking — the lightbox is a bonus, not a substitute for a well-proportioned diagram.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Used `flowchart LR` with many nodes | Diagram overflows the column, text unreadable | Switch to `flowchart TB` or split the diagram |
| Subgraph `direction LR` with external edges | Layout ignores `direction`, still wide | Restructure — avoid subgraphs with external edges |
| Edited a hook partial without restarting server | Lightbox / theme change not visible | Restart `hugo server` |
| Stripped SVG ids | Lightbox shows unstyled diagram | Keep the mermaid-generated SVG id |
| Single giant diagram > 12 nodes | Too dense, overcrowded | Split into focused smaller diagrams |
