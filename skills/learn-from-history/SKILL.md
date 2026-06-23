---
name: learn-from-history
description: Use when the user wants to turn past Claude Code work into reusable automation — invoked as /learn-from-history, optionally with a window like "7d". Triggers include end-of-session review, "what should we automate", "mine my recent sessions", recurring manual workflows, repeated corrections, repeated permission prompts, or preferences worth capturing as a skill, CLAUDE.md entry, or memory.
disable-model-invocation: true
---

# Learn From History

Mine past Claude Code work for **recurring** patterns and turn them into durable, reusable automation: skills, CLAUDE.md entries, memory, and permission allowlists.

> Local skill, maintained in this repo (`.source.json` has `"repo": null`).
> Replaces the old `retrospect` and `workflow-from-chats` skills.

## Core principle

A pattern is worth capturing only if it **recurs** (≥ 2 occurrences across the scope) or the user explicitly asks to keep it.
One-off events are noise — drop them.
The goal is not to grade a session; it is to find the repeated friction and manual workflows that should become reusable assets.

Technical rigor over performative praise.
Every claim needs evidence: session id, turn number, a verbatim quote (≤ 15 words), or a tool-call signature.
No emojis.

## When to use

The user runs `/learn-from-history` explicitly — usually once real work is done, or when they want to mine recent sessions.
Do not invoke unprompted.

- `/learn-from-history` — analyze the **current session**.
- `/learn-from-history 7d` (or "last week") — analyze a **window** of recent sessions.

**Do not use** when: the user asked for a plain summary (just summarize), the scope has < ~4 user-turns of real interaction, or there were no tool calls (nothing to learn from).
Say so and stop.

## Scope and gathering

Default scope is the current session.
Reflect on the in-context conversation first.

- If context was compacted (system-reminders mention compaction, or the earliest turns are missing), run `{baseDir}/find-sessions.sh` to locate the session JSONL and Read the earliest portion to recover missed turns.
- For a window (`Nd`), run `{baseDir}/find-sessions.sh --since N` to list recent session JSONLs across **all** project dirs in the active profile, newest first.
  Recurring automation often spans repos, so scan across projects, not just the current one.
  Read enough of each to extract signals; cite the session by id/path.

## Distill — recurrence-first signal detection

Cluster evidence into candidate patterns.
For each, record: trigger, evidence, **recurrence count**, confidence, and the artifact it should become.

| Recurring pattern | Becomes |
|---|---|
| A multi-step tool sequence done manually ≥ 2× (e.g. fetch→categorize→render) | **Skill** |
| The same correction / nudge (`no`, `don't`, `instead`, `that's not…`) | CLAUDE.md (project fact) or memory (preference) |
| A stated preference repeated (`I prefer`, `always`, `never`) | memory |
| The same tool + command approved repeatedly | permission allowlist |
| Re-explaining the same project context across turns/sessions | CLAUDE.md |
| Repeated web lookups for the same library docs | memory note / use context7 |

Also flag wasted-effort smells as supporting evidence (not artifacts on their own): same file Read ≥ 2× with overlapping ranges, broad search followed by a narrow one on the same corpus, a subagent dispatched for a one-grep task, retries of a failing command without diagnosis between attempts.

## Confidence

- **Strong** — explicit user preference, a workflow-changing correction, or the same pattern across ≥ 2 sessions.
- **Medium** — an accepted workflow or a repeated tool/validation choice the user relied on.
- **Weak** — agent-chosen behavior with no user feedback, or a single ambiguous instance.
- **Contradicted** — evidence points both ways; ask the user before writing anything.

Promote only Strong/Medium to artifacts.
List Weak as "consider"; never auto-apply it.

## Materialize — artifact routing

Route each promoted pattern to exactly one artifact.
Stay composable — delegate, do not reimplement.

- **Skill** — a recurring multi-step workflow with clear triggers.
  Draft a proposal (name, "Use when…" description, trigger, the steps, any scripts), then hand it off.
  **REQUIRED SUB-SKILL:** use `superpowers:writing-skills` to author and validate it under `skills/<name>/`; mark it local with a `{"repo": null}` `.source.json`.
  Do not scaffold skill files by hand here.
- **CLAUDE.md** — a collaborator-visible project fact (build/test commands, invariants, code locations, "always use X helper").
  Applied via `{baseDir}/apply-suggestions.sh`.
- **Memory** — a user-private preference (terse vs verbose, tool choices, workflow habits).
  Applied via `{baseDir}/apply-suggestions.sh`.
- **Permission allowlist** — repeated approvals of the same tool/command.
  Reference the `fewer-permission-prompts` skill to generate the `.claude/settings.json` entries; do not re-implement its logic.

### CLAUDE.md vs. memory

`CLAUDE.md` is collaborator-visible; memory is user-private.

- **CLAUDE.md-worthy** — project facts any contributor benefits from.
  Before proposing, Read the project-root `CLAUDE.md` (via `git rev-parse --show-toplevel`) so proposals don't duplicate it.
- **memory-worthy** — anything phrased as "I prefer" / "I always"; personal workflow habits.
- **neither** — one-off events.
  Require ≥ 2 occurrences OR explicit user feedback ("remember this") to promote; otherwise drop.

## Report shape

Emit exactly this structure, organized by artifact type.
Keep it under ~400 lines; compress, don't truncate.

```
# Learn From History

## Scope
<current session | last N days: M sessions across K projects>
- Interaction: <N user / M assistant turns>

## Summary
<P patterns found> → <A skills, B CLAUDE.md, C memory, D permission>

## Proposed skills
- <name> — <"use when" trigger>. Recurs <N>× (<evidence>). → hand to writing-skills.

## Proposed CLAUDE.md additions
Target file: <absolute path, or "propose new at <path>">
(Unified diff — exactly what apply will write.)

## Proposed memory entries
- name: <slug>
  type: <feedback|user|project|reference>
  description: <one-liner>
  body: |
    <content; Why: and How to apply: for feedback/project types>

## Proposed permission allowlist
- <tool + command pattern> approved <N>× → see fewer-permission-prompts.

## Consider (weak signal, not auto-applied)
- <pattern> — <evidence>.

## Apply?
Reply: `apply skills`, `apply claude`, `apply memory`, `apply all`, or `skip`.
```

## Apply on confirmation

- **`apply skills`** — for each proposed skill, invoke `superpowers:writing-skills` with the drafted proposal.
  Do not write skill files directly.
- **`apply claude` / `apply memory` / `apply all`** — Write the payload (schema below) to `/tmp/learn-from-history-<sessionid-or-timestamp>.json`, then call:

```bash
{baseDir}/apply-suggestions.sh <claude|memory|all> <payload.json>
```

```json
{
  "claude_md": { "path": "/abs/CLAUDE.md", "append": "## Section\n\nBody…\n" },
  "memory": {
    "dir": "/abs/memory",
    "entries": [
      { "filename": "feedback_terse.md",
        "content": "---\nname: …\ndescription: …\nmetadata:\n  type: feedback\n---\n\n<body>\n",
        "index_line": "- [Terse output](feedback_terse.md) — prefers short answers" }
    ]
  }
}
```

(`apply all` runs CLAUDE.md + memory; skills are still applied separately via writing-skills.)

## Anti-patterns

- Do NOT dump the transcript.
  The report is the analysis, not a log.
- Do NOT promote single-occurrence events (unless the user said "remember this").
- Do NOT propose collaborator-facing CLAUDE.md entries for personal preferences (those are memory).
- Do NOT scaffold skill files by hand — always go through `superpowers:writing-skills`.
- Do NOT edit CLAUDE.md or memory files directly — always go through `apply-suggestions.sh` so backups and index updates stay consistent.
- Do NOT re-run tools that already ran in-session to re-verify.
  Reuse prior results.
- Do NOT use performative praise or emojis.
  State a genuine strength in one line under `## Strengths` only if there is one; otherwise omit.

## Scripts

```bash
{baseDir}/find-sessions.sh                 # current session JSONL (most recent for cwd)
{baseDir}/find-sessions.sh --since 7       # recent session JSONLs (last 7 days), newest first
{baseDir}/apply-suggestions.sh <scope> <payload.json>   # apply CLAUDE.md / memory edits
```
