---
name: author-mermaid-diagram
description: Use when adding or fixing a mermaid diagram in a Hugo (or other static-site) page so it renders readably inline in a narrow content column (triggers "add a diagram", "mermaid", "diagram is too wide"). Covers the width rule, layout direction, the semantic color palette, and the browser viewBox check.
---

# Authoring Mermaid Diagrams

Most static-site themes render mermaid from a ` ```mermaid ` fence or a `{{< mermaid >}}` shortcode; the constraints below are the same everywhere.

## Width Rule

The critical constraint: the content column is typically ~800 px, so a diagram whose natural (viewBox) width exceeds ~900–950 px shrinks until its text is unreadable inline.
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
Do not use `classDiagram` — it exceeds the width rule and is seldom the right tool for documentation flows.

## Step Numbers on Arrows

Label numbered steps as `-->|"<b>1.</b> description"|` — the `<b>` renders bold via the project's stylesheet.
Never use circled glyphs (①②③).
`sequenceDiagram` uses `autonumber` instead of manual labels.

## Palette — color nodes by semantic role

A single-color theme hides meaning in flow/sequence diagrams.
Apply a small semantic palette via `classDef` so role reads at a glance in light and dark mode.
Mid-tone Tailwind 400/500 fills with white text:

| Class | Use for | Fill | Stroke |
|---|---|---|---|
| `leader` | Active / primary actor | `#10b981` | `#047857` |
| `standby` | Passive / waiting | `#94a3b8` | `#475569` |
| `lease` | Coordination primitive (lock, lease, bucket) | `#f59e0b` | `#b45309` |
| `resource` | Resource being acted on | `#fb7185` | `#be123c` |
| `external` | External system (API, gateway) | `#64748b` | `#334155` |
| `process` | Logic / decision / generic step | `#38bdf8` | `#0369a1` |

All classes use `color:#fff`.
Rules:
- Only declare the classes a diagram needs.
- Once you class one node, class **every** node (mixing classed and unclassed nodes looks broken).
- Append `classDef` and `class` lines at the bottom of the diagram body, before the closing fence/shortcode.
- Inside a `subgraph`, put the `classDef`/`class` lines **after** the matching `end`.

## Theme notes

Theme-specific gotchas (verify for yours):

- **Docsy caches partials**: after editing `body-end.html` (or any hook partial), restart `hugo server` — live reload serves the stale partial.
- **Lightbox keeps SVG ids**: the click-to-zoom lightbox clones the SVG and scopes its embedded CSS to the original `id`.
  Do not strip ids from mermaid output.

Diagrams must be readable inline without clicking — the lightbox is a bonus, not a substitute for a well-proportioned diagram.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Used `flowchart LR` with many nodes | Diagram overflows the column, text unreadable | Switch to `flowchart TB` or split the diagram |
| Subgraph `direction LR` with external edges | Layout ignores `direction`, still wide | Restructure — avoid subgraphs with external edges |
| Edited a hook partial without restarting server | Lightbox / theme change not visible | Restart `hugo server` |
| Stripped SVG ids | Lightbox shows unstyled diagram | Keep the mermaid-generated SVG id |
| Single giant diagram > 12 nodes | Too dense, overcrowded | Split into focused smaller diagrams |
