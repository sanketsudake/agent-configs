---
name: retrospect
description: Use at the end of a session to analyze how the interaction went - find user nudges/course-corrections, redundant tool calls, wasted tokens, skills that should have been invoked, and permission-prompt churn. Produces a structured report and proposes durable fixes (CLAUDE.md entries for project collaborators, auto-memory entries for user preferences), then applies them on confirmation. Invoked as /retrospect.
---

# Retrospect

Post-session retrospective. Produces a structured report of what went well, what wasted tokens, where the user had to course-correct, which available skills were missed, and which durable fixes would prevent the same issues next time.

> Local skill, not vendored from upstream `pi-skills`. If upstream ever ships a skill named `retrospect`, `make sync-skills` will overwrite this file. Low probability; re-copy from git if it happens.

## When to Use

The user explicitly runs `/retrospect` — usually once real work is mostly done and before closing the session. Do not invoke unprompted. Do not run on sessions with fewer than ~4 user-turns; say "too little interaction to retrospect" and stop.

## Core principle

Technical rigor over performative praise. State findings factually. Require evidence (turn number, quoted phrase, tool-call signature) for every claim. No emojis.

## Procedure

```
1. REFLECT on the in-context conversation. Extract signals (see "Signal detection").
2. IF context was compacted (system-reminders mention compaction, or earliest
   turns are missing): run {baseDir}/find-session.sh to locate the session
   JSONL, then Read the earliest portion to recover missed turns.
3. CLASSIFY each finding into [Critical] / [Important] / [Minor].
4. CLASSIFY each proposed durable fix into CLAUDE.md (project fact) vs.
   memory (user preference). Drop single-occurrence items that don't qualify.
5. EMIT the report in the exact shape below.
6. WAIT for user reply: `apply`, `apply claude`, `apply memory`, or `skip`.
7. ON apply: call {baseDir}/apply-suggestions.sh with a JSON payload and
   report per-file outcome.
```

## Signal detection

### [Critical] — Nudges and systemic drift

Look for user messages containing corrective phrasing: `no`, `don't`, `stop`, `wait`, `actually`, `instead`, `wrong`, `not what I asked`, `that's not…`. Cluster consecutive corrections in the same user turn as one nudge event.

Also flag:
- User re-stating the original request after Claude acted → Claude misread intent.
- Same correction appearing twice in one session → promote to a `CLAUDE.md` candidate.

For each nudge, record: turn number, verbatim quote (≤ 15 words), what Claude did wrong, what was needed.

### [Important] — Wasted tokens

- Same file `Read` ≥ 2× with overlapping line ranges → should have been one wide Read.
- Broad `grep`/`find` followed within 2 turns by a narrower search on the same corpus → over-exploration.
- Retries of a failing `Bash` command without diagnosis between attempts.
- `Agent` / `Explore` subagent dispatched for a task resolvable with one grep.
- `Read` without `limit` on a file > ~500 lines when only a small region was needed.
- If JSONL is available, sum per-turn `message.usage` fields and list the top 3 most expensive turns with brief attribution (large Read, wide Agent fan-out, re-prompted compaction).

### [Important] — Skills that should have been invoked

Use the skill list from the *current* system prompt (don't hardcode — it drifts). Shape-to-skill heuristics to seed:

- Multi-step code change without `superpowers:writing-plans` / `executing-plans`.
- Debugging / test-failure diagnosis without `superpowers:systematic-debugging`.
- New-feature creative work without `superpowers:brainstorming`.
- Completion claim ("done", "fixed", "all tests pass") without `superpowers:verification-before-completion`.
- Post-implementation without a `simplify` pass.
- Settings / permission / hook changes done ad-hoc instead of via `update-config`.
- Repeated web searches for library docs instead of using context7.

### [Minor] — Permission-prompt churn

Look for repeated user approvals of the same tool + command pattern (e.g. user approved `Bash(npm test)` three times). For each, propose a `.claude/settings.json` allowlist entry and **reference** the `fewer-permission-prompts` skill — do not re-implement its logic.

### [Minor] — Workflow smells

- Plan mode entered and exited multiple times → planning was fragmented.
- Multi-step work done without `TaskCreate`.
- Trailing "let me check" narration with no follow-up action.
- Large `Read` followed immediately by re-reading the same region — cache miss caused by an intermediate compaction.

## CLAUDE.md vs. memory classification

This distinction matters because `CLAUDE.md` is **collaborator-visible** and memory is **user-private**.

- **CLAUDE.md-worthy** — project facts: build / test / deploy commands, architectural invariants, code locations, "never edit `gen/`", "always use the X helper instead of Y". Things any contributor would benefit from.
- **memory-worthy** — user preferences: terse-vs-verbose output, specific tool choices, workflow habits, "I prefer `gh pr create`-then-attach over …". Anything phrased as "I prefer" or "I always".
- **neither** — one-off events. Require ≥ 2 occurrences in this session OR explicit user feedback ("don't do that again", "remember this") to qualify for promotion. Otherwise, drop.

Before proposing `CLAUDE.md` additions, Read the existing `CLAUDE.md` at the project root (via `git rev-parse --show-toplevel`) if present, so proposals don't duplicate what's already there. If no `CLAUDE.md` exists, propose creating one only if there are ≥ 2 qualifying entries.

## Output shape

Emit exactly this structure. Keep the body under ~400 lines regardless of session size — compress by tier, not by truncation.

```
# Session Retrospective

## Summary
- Turns: <N user / M assistant>
- Nudges: <N> (<M> critical)
- Estimated waste: ~<X> tokens (<Y>% of session, if JSONL available)
- Skills missed: <K>
- Suggestions: <A> CLAUDE.md, <B> memory

## [Critical]
- <short title> — turn <N>: "<verbatim quote>". <what was wrong, one line>. <what was needed>.

## [Important]
- <title> — <evidence>. <recommendation>.

## [Minor]
- <title> — <evidence>.

## Proposed CLAUDE.md additions
Target file: <absolute path, or "propose new at <path>">
(Unified diff — exactly what apply will write.)

## Proposed memory entries
- name: <slug>
  type: <feedback|user|project|reference>
  description: <one-liner>
  body: |
    <content, with Why: and How to apply: for feedback/project types>

## Apply?
Reply `apply`, `apply claude`, `apply memory`, or `skip`.
```

## Apply on confirmation

When the user replies `apply` / `apply claude` / `apply memory`, call:

```bash
{baseDir}/apply-suggestions.sh <scope> <payload.json>
```

Where `<scope>` is `all`, `claude`, or `memory`, and `<payload.json>` is a temp file containing exactly what you proposed, in this schema:

```json
{
  "claude_md": {
    "path": "/absolute/path/to/CLAUDE.md",
    "append": "## Section title\n\nBody text…\n"
  },
  "memory": {
    "dir": "/Users/…/.claude-personal/projects/-Users-…/memory",
    "entries": [
      {
        "filename": "feedback_terse_output.md",
        "content": "---\nname: …\ndescription: …\ntype: feedback\n---\n\n<body>\n",
        "index_line": "- [Terse output](feedback_terse_output.md) — prefers short answers"
      }
    ]
  }
}
```

Write the payload with the `Write` tool to a path under `/tmp/retrospect-<sessionid-or-timestamp>.json`, then invoke the script.

## Anti-patterns

- Do NOT dump the full transcript. The report is the analysis, not a log.
- Do NOT promote single-occurrence events to rules (unless user explicitly asked to remember).
- Do NOT suggest collaborator-facing `CLAUDE.md` entries for personal preferences.
- Do NOT use performative praise ("great session!"). If there's a strength worth naming, state it in one line under a `## Strengths` block; otherwise omit.
- Do NOT use emojis in output.
- Do NOT re-run tools that already ran in-session to re-verify. Reuse prior results.
- Do NOT edit `CLAUDE.md` or write memory files directly from within the skill — always go through `apply-suggestions.sh` so backups and index updates stay consistent.

## Scripts

```bash
{baseDir}/find-session.sh                 # Prints path to the current session JSONL, or exits non-zero
{baseDir}/apply-suggestions.sh <scope> <payload.json>   # Applies approved edits
```

## When NOT to use

- Session has fewer than ~4 user-turns.
- User said "just summarize" — use a plain summary instead, not this skill.
- Session was purely conversational (no tool calls) — nothing to retrospect on.
