# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A dotfiles-style config repo that provisions two tools across two Claude profiles (personal/work):

- **pi** (the `pi-mono` coding agent) — config lives under `pi/` and is stowed into `~/.pi` via GNU stow.
- **Claude Code** — a shared global `CLAUDE.md` and a shared `skills/` directory are symlinked into `~/.claude-personal/` and `~/.claude-work/`.

There is no application to build/test/lint. The `Makefile` is the primary interface.

## Makefile targets

- `make install` — runs `link-skills`, `link-claude-md`, then `stow --adopt pi` into `~/.pi`. Safe to re-run; it replaces existing symlinks and backs up real files it would overwrite.
- `make uninstall` — reverses the above.
- `make sync-skills` — clones/pulls `github.com/badlogic/pi-skills` into `/tmp/pi-skills` and copies each skill dir into `./skills/`. Skills are vendored, so local edits to files under `skills/<upstream-name>/` are overwritten on next sync.
- `make sync-extensions` — clones/pulls `github.com/badlogic/pi-mono` into `/tmp/pi-mono` and copies the whitelisted set (see `PI_EXTENSIONS` in the Makefile) from `packages/coding-agent/examples/extensions` into `./pi/extensions/`. Same vendoring caveat applies.
- `make plugins-check` — diffs `claude/plugins.txt` (desired, user-scoped) against `<CLAUDE_CONFIG_DIR>/plugins/installed_plugins.json` for each profile, reporting missing/extra. Install missing ones manually with `/plugin install <name>` inside the target profile. Requires `jq`.

## Architecture notes that are easy to miss

- **Two Claude profiles via `CLAUDE_CONFIG_DIR`.** `scripts/claude-multi-account.sh` is documentation (shell-function snippets to copy into `~/.zprofile`), not something that runs. The `pclaude`/`wclaude` wrappers set `CLAUDE_CONFIG_DIR` to `~/.claude-personal` or `~/.claude-work`. Both dirs share the same `CLAUDE.md` and `skills/` via symlinks maintained by the Makefile — changes to `claude/CLAUDE.md` or `skills/` immediately apply to both profiles.
- **`claude/CLAUDE.md` is the shared global user CLAUDE.md**, not this file. It gets symlinked to `~/.claude-personal/CLAUDE.md` and `~/.claude-work/CLAUDE.md` by `link-claude-md`. Keep it minimal and profile-agnostic.
- **`pi/` is stowed with `--adopt`.** On first `make install`, stow moves any pre-existing files in `~/.pi` into this repo, replacing them with symlinks. That means `pi/agent/settings.json`, `pi/extensions/*.ts`, and `pi/prompts/` are the live files the agent reads — edits here take effect immediately in `~/.pi/...`. The `.pi/` directory in the repo root is unrelated scaffolding (empty).
- **`pi/extensions/subagent/` is a directory extension** (listed without `.ts` suffix in `PI_EXTENSIONS`); the rest are single-file TS extensions. Adding a new upstream extension requires editing `PI_EXTENSIONS` in the Makefile.
- **`skills/` is the single source of truth** for skills across pi and both Claude profiles. `link-skills` symlinks `$(CURDIR)/skills` into `~/.pi/skills`, `~/.claude-personal/skills`, `~/.claude-work/skills`.
- **`plugins.txt` is desired-state only.** Installation is manual per-profile; the Makefile only reports drift. Lines are `<name>@<marketplace>`; blanks and `#` comments are ignored.

## Conventions when editing

- Treat `skills/` and `pi/extensions/` as vendored unless intentionally diverging from upstream — a re-sync clobbers local edits. If you do diverge, note it somewhere durable (commit message or a comment in the file) because there's no automated drift detection against upstream.
- When adding a new profile, update `CLAUDE_CONFIG_DIRS` (Makefile line 9) — it drives both the CLAUDE.md and skills symlink loops.
