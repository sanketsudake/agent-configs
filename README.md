# harness-configs

Portable AI coding-harness configs: shared skills, commands, rules, agents, and settings for [Claude Code](https://claude.com/claude-code) and the [pi](https://github.com/badlogic/pi-mono) coding agent, provisioned across multiple profiles from one source of truth.

This is a personal dotfiles-style repo, not a product.
It is published so other AI developers can borrow the architecture and the tooling.
Paths are hardcoded to one machine; adapt them before adopting (see [Adopt it](#adopt-it)).

## Ideas worth stealing

- **One source of truth, many harnesses.**
  A single `skills/` tree feeds Claude Code *and* pi.
  `claude/` config is symlinked into two Claude profiles; `pi/` is stowed into `~/.pi`.
  Edit once, every harness sees it immediately.
- **Two Claude profiles via `CLAUDE_CONFIG_DIR`.**
  `pclaude` / `wclaude` wrappers point Claude Code at `~/.claude-personal` or `~/.claude-work`, so personal and work accounts stay isolated but share the same skills and global instructions.
- **Per-resource source tracking.**
  Each fetched skill/agent carries a `.source.json` sidecar recording its origin repo, subpath, ref, and resolved commit, so it can be updated later with one command — vendoring without losing provenance.
- **Guardrail extensions for pi.**
  Confirm-before-destructive, dirty-repo guard, protected paths, and a permission gate run as agent extensions, not as hope.
- **Desired-state plugins.**
  `plugins.txt` is the declared plugin set; `make plugins-check` reports drift per profile.

## Layout

```
harness-configs/
├── Makefile               # primary interface — all <resource>-<action> targets
├── CLAUDE.md              # guide for agents working IN this repo
├── claude/                # Claude Code config, symlinked into both profiles
│   ├── CLAUDE.md          # shared global user instructions (both profiles)
│   ├── commands/          # slash commands
│   ├── agents/            # subagents (+ .source.json sidecars)
│   ├── rules/             # rule files
│   ├── scripts/           # helper scripts referenced by CLAUDE.md
│   └── plugins.txt        # desired-state plugin list
├── skills/                # shared skills for Claude + pi (source of truth)
│   └── <name>/SKILL.md    # each with a .source.json sidecar
├── pi/                    # pi agent config, stowed into ~/.pi
│   ├── agent/settings.json
│   ├── prompts/
│   └── extensions/        # TypeScript extensions (+ subagent/ dir extension)
└── scripts/               # repo tooling (not symlinked into profiles)
    ├── resource-manager.sh    # fetch/track/update skills & agents
    └── claude-multi-account.sh # pclaude/wclaude wrapper snippets
```

## How it wires together

`make install` provisions everything and is safe to re-run:

- Symlinks `skills/` into `~/.pi/skills`, `~/.claude-personal/skills`, `~/.claude-work/skills`.
- Symlinks `claude/CLAUDE.md`, `commands/`, `rules/`, `scripts/`, `agents/` into both Claude profiles.
- Stows `pi/` into `~/.pi` (settings, prompts, extensions).

Because `skills/` and `claude/` are symlinks, an edit in this repo applies to every profile and both harnesses at once — no copy step.
The `Makefile` derives all paths from `$(CURDIR)`, so the repo can live anywhere.

## What's inside

### Skills

Shared by Claude Code and pi.
Most are fetched from upstream repos and tracked via `.source.json`; a few are authored here.
Run `make skills-list` to see each one's source and status.

| Skill | Purpose |
|-------|---------|
| `brave-search` | Web search and content extraction via the Brave Search API; no browser needed. |
| `browser-tools` | Interactive browser automation via the Chrome DevTools Protocol. |
| `deslop` | Remove AI-generated code slop and clean up code style. |
| `gccli` | Google Calendar CLI: list calendars, view/create/update events, check availability. |
| `gdcli` | Google Drive CLI: list, search, upload, download, and share files and folders. |
| `gmcli` | Gmail CLI: search, read threads, send, manage drafts, labels, and attachments. |
| `harvest-automation` | Mine past Claude Code sessions for recurring patterns; turn them into skills, CLAUDE.md entries, and memory. |
| `make-pr-easy-to-review` | Clean noisy history, improve PR descriptions, and annotate diffs without changing behavior. |
| `pr-review-canvas` | Generate an interactive HTML PR-review walkthrough from `gh` API data. |
| `source-code-for-gh-advisory` | Obtain and reproduce the vulnerable source referenced by a GHSA/CVE. |
| `thermo-nuclear-code-quality-review` | Extremely strict maintainability review (abstraction, giant files, spaghetti). |
| `transcribe` | Local speech-to-text on Apple Silicon macOS. |
| `vscode` | VS Code integration for viewing diffs and comparing files. |
| `youtube-transcript` | Fetch YouTube transcripts for summarization and analysis. |

### Claude commands, agents, rules

- **Command** `/history` — read the global conversation history and present it in a scannable format.
- **Agent** `thermo-nuclear-code-quality-review` — strict maintainability audit (1k-line rule, spaghetti, code-judo), driven by the matching skill.
- **Rules** — `claude/rules/` is wired up for rule files (currently empty).

### Shared `CLAUDE.md`

Profile-agnostic global instructions applied to both Claude accounts:

- Never publish secrets; never commit `.env`.
- Markdown one-sentence-per-line, with a reusable formatter at `claude/scripts/md-one-sentence-per-line.py`.

### pi extensions

TypeScript extensions stowed into `~/.pi/extensions`, vendored from the [pi-mono](https://github.com/badlogic/pi-mono) examples:

| Extension | Purpose |
|-----------|---------|
| `confirm-destructive` | Confirm before destructive actions. |
| `dirty-repo-guard` | Guard against operating on a dirty git repo. |
| `protected-paths` | Block edits to protected paths. |
| `permission-gate` | Gate tool permissions. |
| `handoff` | Transfer context to a new focused session. |
| `notify` | Surface notifications on events. |
| `mac-system-theme` | Sync the pi theme with macOS dark/light mode. |
| `status-line` | Custom status line. |
| `todo` | Todo state via session entries (state-management demo). |
| `subagent/` | Subagent dispatch (directory extension). |

### Plugins

`claude/plugins.txt` is the desired, user-scoped plugin set (installed manually per profile): `superpowers`, `frontend-design`, `context7`, `gopls-lsp`, `pr-review-toolkit`, `serena` — all from `claude-plugins-official`.

## Adopt it

Prerequisites: `git`, [GNU `stow`](https://www.gnu.org/software/stow/), and `jq`.
`gh` is needed only for the GitHub-facing skills; `python3` only for the markdown formatter.

```sh
git clone https://github.com/sanketsudake/harness-configs.git ~/personal/harness-configs
cd ~/personal/harness-configs
```

Before `make install`, adapt the parts that are personal to this machine:

- **Profiles.**
  `CLAUDE_CONFIG_DIRS` in the `Makefile` lists `~/.claude-personal` and `~/.claude-work`.
  Change, add, or remove profiles there.
- **Wrappers.**
  Copy the `pclaude` / `wclaude` snippets from `scripts/claude-multi-account.sh` into your shell profile, pointing `CLAUDE_CONFIG_DIR` at your dirs.
- **Global rules.**
  `claude/CLAUDE.md` is opinionated — make it yours.

Then:

```sh
make install      # symlink claude/ + skills/ into profiles, stow pi/ into ~/.pi
make skills-list  # see each skill's source and status
```

`make uninstall` reverses it.

## Makefile reference

All targets follow `<resource>-<action>`; `install` / `uninstall` are the aggregates.

| Target | Does |
|--------|------|
| `install` / `uninstall` | Link/stow everything into the profiles, or reverse it. |
| `skills-sync` | Bulk-vendor the [pi-skills](https://github.com/badlogic/pi-skills) set into `skills/`. |
| `extensions-sync` | Vendor the whitelisted pi-mono extensions into `pi/extensions/`. |
| `skills-fetch REPO=… SUBPATH=…` | Fetch one skill from any repo/subpath and write its `.source.json`. |
| `agents-fetch REPO=… SUBPATH=…` | Same, for a single agent `.md` file. |
| `skills-list` / `agents-list` | Table of every resource with status (`remote`/`local`/`unmanaged`) and source. |
| `skills-update NAME=…` / `-update-all` | Re-resolve the recorded ref and re-copy if upstream moved. |
| `skills-delete NAME=…` | Remove a resource and its sidecar. |
| `plugins-check` | Diff `plugins.txt` against each profile's installed plugins. |
| `plugins-sync` | Emit the exact `/plugin install` lines to close the drift. |

`agents-*` twins exist for every `skills-*` target.
Use `SUBPATH=`, never `PATH=` — the latter would clobber the shell `PATH` inside recipes.

## Notes

- `skills/` and `pi/extensions/` are treated as vendored.
  A re-sync or `skills-update` overwrites local edits — diverge intentionally and note it durably.
- A `.source.json` is regenerated on fetch/update, so don't hand-edit it; locally authored resources carry `{"repo": null}` and survive `update-all` untouched.
- Plugin installation is manual per profile — Claude Code has no headless `/plugin install`; the Makefile only reports drift.
