# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A dotfiles-style config repo that provisions two tools across two Claude profiles (personal/work):

- **pi** (the `pi-mono` coding agent) — config lives under `pi/` and is stowed into `~/.pi` via GNU stow.
- **Claude Code** — a shared global `CLAUDE.md`, `skills/`, `commands/`, and `rules/` are symlinked into `~/.claude-personal/` and `~/.claude-work/`.

There is no application to build/test/lint.
The `Makefile` is the primary interface.

## Makefile targets

All targets follow a `<resource>-<action>` naming convention (e.g. `skills-link`, `skills-sync`), except the `install`/`uninstall` aggregates.

- `make install` — runs `skills-link`, `claude-md-link`, `commands-link`, `rules-link`, `scripts-link`, `agents-link`, then `stow --adopt pi` into `~/.pi`.
  Safe to re-run; it replaces existing symlinks and backs up real files it would overwrite.
- `make uninstall` — reverses the above.
- `make skills-sync` — clones/pulls `github.com/badlogic/pi-skills` into `/tmp/pi-skills` and copies each skill dir into `./skills/`.
  Bulk vendoring of the badlogic set; local edits to files under those `skills/<upstream-name>/` dirs are overwritten on next sync.
  For single skills from arbitrary repos, use `skills-fetch` (see "Skill & agent source management" below).
- `make extensions-sync` — clones/pulls `github.com/badlogic/pi-mono` into `/tmp/pi-mono` and copies the whitelisted set (see `PI_EXTENSIONS` in the Makefile) from `packages/coding-agent/examples/extensions` into `./pi/extensions/`.
  Same vendoring caveat applies.
- `make plugins-check` — diffs `claude/plugins.txt` (desired, user-scoped) against `<CLAUDE_CONFIG_DIR>/plugins/installed_plugins.json` for each profile, reporting missing/extra.
  Requires `jq`.
- `make plugins-sync` — same diff as `plugins-check` but emits the exact `/plugin install <name>` lines per profile, prefixed with the wrapper to enter (`pclaude` / `wclaude`).
  Copy-paste into a session in the right profile to close the drift.
  Installation itself stays manual — Claude Code has no headless `/plugin install`.

## Skill & agent source management

`scripts/resource-manager.sh` (wrapped by the `skills-*` and `agents-*` make targets) fetches individual **skills** or **agents** from any git repo at any subpath and tracks where each came from, so they can be updated later.
It is repo tooling and lives in top-level `scripts/`, not `claude/scripts/` — it is not symlinked into the profiles.
Requires `git` and `jq`.

The tool takes a leading `--kind skill|agent`; the make targets supply it.
The two kinds differ only in structure:

- A **skill** is a directory under `skills/` validated by a `SKILL.md`; its sidecar lives **inside** at `skills/<name>/.source.json`.
- An **agent** is a single `.md` file under `claude/agents/`; its sidecar is a **sibling** at `claude/agents/<name>.source.json`.

Each managed resource carries a `.source.json` sidecar:

- **remote** — `{"repo","subpath","ref","commit","fetched_at"}`, where `commit` is the resolved SHA of `ref` at fetch time.
- **local** — `{"repo": null, ...}` for resources authored in this repo (e.g. the `learn-from-history` skill); `update` and `delete` treat them as having no upstream.
- A resource with no `.source.json` is reported as `unmanaged`.

Targets (each `skills-*` has an `agents-*` twin taking the same variables):

- `make skills-fetch REPO=owner/name SUBPATH=path/to/skill [REF=main] [NAME=…] [FORCE=1]` — shallow sparse-clone, validate the subpath, copy it into `skills/<NAME>/`, and write the sidecar.
  Refuses to overwrite unless `FORCE=1`.
  A full GitHub URL also works: `URL='https://github.com/owner/name/tree/<ref>/<subpath>'`.
- `make agents-fetch REPO=owner/name SUBPATH=path/to/agent.md [REF=main] [NAME=…] [FORCE=1]` — same, but the subpath is a `.md` file (NAME defaults to its basename minus `.md`), copied into `claude/agents/<NAME>.md`.
  Accepts a `/blob/` URL too.
- `make skills-list` / `make agents-list` — table of every resource with its status (`remote`/`local`/`unmanaged`) and source.
- `make skills-update NAME=…` / `make agents-update NAME=…` — re-resolve the recorded `ref`; if the upstream commit moved, re-copy and rewrite the sidecar (prints `old→new`), else report up to date.
  Skips `local` and `unmanaged`.
- `make skills-update-all` / `make agents-update-all` — update every remote resource of that kind.
- `make skills-delete NAME=… [YES=1]` / `make agents-delete NAME=… [YES=1]` — remove the resource (for agents, both the `.md` and its sidecar); prompts unless `YES=1`.

Note: the make variable is `SUBPATH`, not `PATH` — `PATH=` on a make command line would clobber the shell `PATH` inside recipes and break `git`/`jq`.

## Architecture notes that are easy to miss

- **Two Claude profiles via `CLAUDE_CONFIG_DIR`.**
  `scripts/claude-multi-account.sh` is documentation (shell-function snippets to copy into `~/.zprofile`), not something that runs.
  The `pclaude`/`wclaude` wrappers set `CLAUDE_CONFIG_DIR` to `~/.claude-personal` or `~/.claude-work`.
  Both dirs share the same `CLAUDE.md` and `skills/` via symlinks maintained by the Makefile — changes to `claude/CLAUDE.md` or `skills/` immediately apply to both profiles.
- **`claude/CLAUDE.md` is the shared global user CLAUDE.md**, not this file.
  It gets symlinked to `~/.claude-personal/CLAUDE.md` and `~/.claude-work/CLAUDE.md` by `claude-md-link`.
  Keep it minimal and profile-agnostic.
- **`pi/` is stowed with `--adopt`.**
  On first `make install`, stow moves any pre-existing files in `~/.pi` into this repo, replacing them with symlinks.
  That means `pi/agent/settings.json`, `pi/extensions/*.ts`, and `pi/prompts/` are the live files the agent reads — edits here take effect immediately in `~/.pi/...`.
  The `.pi/` directory in the repo root is unrelated scaffolding (empty).
- **`pi/extensions/subagent/` is a directory extension** (listed without `.ts` suffix in `PI_EXTENSIONS`); the rest are single-file TS extensions.
  Adding a new upstream extension requires editing `PI_EXTENSIONS` in the Makefile.
- **`skills/` is the single source of truth** for skills across pi and both Claude profiles.
  `skills-link` symlinks `$(CURDIR)/skills` into `~/.pi/skills`, `~/.claude-personal/skills`, `~/.claude-work/skills`.
- **`claude/commands/`, `claude/rules/`, `claude/scripts/`, and `claude/agents/`** are the single source of truth for user-scoped slash commands, rules, helper scripts, and subagents across both Claude profiles.
`commands-link` / `rules-link` / `scripts-link` / `agents-link` symlink them into `~/.claude-personal/` and `~/.claude-work/` (not into `~/.pi/` — pi doesn't consume these; pi has its own vendored `pi/extensions/subagent/agents/`).
The shared `CLAUDE.md` references scripts via `$CLAUDE_CONFIG_DIR/scripts/...` so the path resolves correctly under either profile.
Agents are single `.md` files fetched and tracked by `resource-manager.sh` (see "Skill & agent source management").
- **`plugins.txt` is desired-state only.**
  Installation is manual per-profile; the Makefile only reports drift.
  Lines are `<name>@<marketplace>`; blanks and `#` comments are ignored.

## Conventions when editing

- Keep skills atomic, easy to maintain, and reusable/composable.
  Each skill should do one well-scoped thing so it can be invoked on its own or chained with others, rather than bundling several unrelated workflows.
  Prefer extracting shared logic into a script the skill calls over duplicating it across skills, and keep `SKILL.md` focused enough that another skill (or the model) can lean on it without inheriting unrelated behavior.
  When a skill needs another skill, reference it by name as a soft dependency instead of copying its contents.
- Treat `skills/` and `pi/extensions/` as vendored unless intentionally diverging from upstream — a re-sync (or `skills-update`) clobbers local edits.
  If you do diverge, note it somewhere durable (commit message or a comment in the file) because there's no automated drift detection against upstream.
- A resource's `.source.json` sidecar is regenerated by `resource-manager.sh` on fetch/update, so don't hand-edit it expecting persistence; change the source by re-fetching.
  Resources authored here (no upstream) keep a `{"repo": null}` sidecar so they survive `skills-update-all` / `agents-update-all` untouched.
- When adding a new profile, update `CLAUDE_CONFIG_DIRS` (Makefile line 9) — it drives both the CLAUDE.md and skills symlink loops.
