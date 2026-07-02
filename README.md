# harness-configs

Portable AI coding-harness configs: shared skills, commands, rules, agents, and settings for [Claude Code](https://claude.com/claude-code) and the [pi](https://github.com/badlogic/pi-mono) coding agent, provisioned across multiple profiles from one source of truth.

A personal dotfiles-style repo, published so others can borrow the architecture.
Paths are hardcoded to one machine — adapt before adopting (see [Adopt it](#adopt-it)).

## Ideas worth stealing

- **One source of truth, many harnesses.** A single `skills/` tree feeds Claude Code *and* pi; edit once, every harness sees it immediately.
- **Two Claude profiles via `CLAUDE_CONFIG_DIR`.** `pclaude` / `wclaude` wrappers keep personal and work accounts isolated but sharing the same skills and rules.
- **Per-resource source tracking.** Every skill/agent carries a `.source.json` sidecar (origin repo, subpath, ref, commit) so vendored resources update with one command.
- **Generated catalog, validated by a doctor.** `skills/README.md` is generated from sidecar metadata; `make skills-doctor` fails when anything drifts.
- **Guardrail extensions for pi.** Confirm-before-destructive, dirty-repo guard, protected paths — extensions, not hope.
- **Desired-state plugins.** `plugins.txt` declares the plugin set; `make plugins-check` reports drift per profile.
- **Borrow skills.sh discovery without adopting its model.** `make skills-find` / `skills-add` front the [`skills`](https://github.com/vercel-labs/skills) CLI but pipe results back into this repo's own vendoring.

## Layout

```
harness-configs/
├── Makefile               # primary interface — all <resource>-<action> targets
├── CLAUDE.md              # guide for agents working IN this repo
├── claude/                # Claude Code config, symlinked into both profiles
│   ├── CLAUDE.md          # shared global user instructions
│   ├── commands/          # slash commands
│   ├── agents/            # subagents (+ .source.json sidecars)
│   ├── rules/             # rule files (model routing, git hygiene, delegation)
│   ├── scripts/           # helper scripts (md formatter, statusline hook)
│   └── plugins.txt        # desired-state plugin list
├── skills/                # shared skills for Claude + pi (source of truth)
│   ├── README.md          # generated catalog — start here
│   └── <name>/SKILL.md    # each with a .source.json sidecar
├── pi/                    # pi agent config, stowed into ~/.pi
└── scripts/               # repo tooling (not symlinked into profiles)
```

`make install` symlinks `skills/` and `claude/*` into `~/.pi` and both Claude profiles and stows `pi/`; safe to re-run.
Everything is symlinked, so an edit here applies to every profile and both harnesses at once.

## Skills

**Browse the [skills catalog](skills/README.md)** — all skills grouped by category, generated from each skill's sidecar (`make skills-catalog`).

Most are authored here (`local`); the rest are vendored from [pi-skills](https://github.com/badlogic/pi-skills), [cursor-team-kit](https://github.com/cursor/plugins), [anthropics/skills](https://github.com/anthropics/skills), and the [skills.sh](https://www.skills.sh/) ecosystem.
Categories are sidecar metadata, not folders — Claude Code and pi only scan `skills/` one level deep.
To add more: `make skills-find Q=…` to discover, `make skills-add SOURCE=owner/repo@skill CATEGORY=…` to vendor.

## Agents & rules

| Agent | Purpose |
|-------|---------|
| `plan-reviewer` | Pre-execution plan review against the actual codebase; APPROVE/REVISE with evidence. |
| `bulk-mechanic` | Haiku executor for mechanical, judgment-free batches. |
| `pr-shepherd` | Drives the push → CI → bot-review loop to green. |
| `skill-auditor` | Audits a skill directory against this repo's conventions. |
| `thermo-nuclear-code-quality-review` | Strict maintainability audit (vendored from cursor-team-kit). |

| Rule | Governs |
|------|---------|
| `model-routing.md` | Cheapest reliable model tier per task (haiku mechanical / sonnet routine / session model for judgment) and effort calibration. |
| `git-hygiene.md` | Staging, commit, and push discipline. |
| `delegation.md` | When to hand work to the agents above instead of doing it inline. |

Plus: the `/history` command, the shared `CLAUDE.md` (secrets hygiene, one-sentence-per-line markdown, rules pointer), helper scripts (`md-one-sentence-per-line.py`, `statusline-command.sh`), pi guardrail extensions vendored from [pi-mono](https://github.com/badlogic/pi-mono), and the desired-state plugin list in `claude/plugins.txt`.

## Adopt it

Prerequisites: `git`, [GNU `stow`](https://www.gnu.org/software/stow/), `jq`; `gh`/`python3`/`npx` only for the skills that use them.

```sh
git clone https://github.com/sanketsudake/harness-configs.git
cd harness-configs
# 1. Edit CLAUDE_CONFIG_DIRS in the Makefile (profiles)
# 2. Copy the pclaude/wclaude snippets from scripts/claude-multi-account.sh into your shell profile
# 3. Make claude/CLAUDE.md yours — it's opinionated
make install      # symlink claude/ + skills/ into profiles, stow pi/ into ~/.pi
make skills-list  # see each skill's source and status
```

`make uninstall` reverses it.

## Makefile reference

All targets follow `<resource>-<action>`; `install` / `uninstall` are the aggregates.

| Target | Does |
|--------|------|
| `install` / `uninstall` | Link/stow everything into the profiles, or reverse it. |
| `skills-find [Q=… OWNER=…]` | Discover skills on [skills.sh](https://www.skills.sh/). |
| `skills-add SOURCE=… [SKILL=… CATEGORY=…]` | Fetch via the `skills` CLI and vendor with a `.source.json`. |
| `skills-fetch REPO=… SUBPATH=… [CATEGORY=…]` | Fetch one skill from any repo/subpath. |
| `skills-list` | Every skill with status and source, grouped by category. |
| `skills-category NAME=… CATEGORY=…` | Set/replace a skill's category (survives updates). |
| `skills-catalog [CHECK=1]` | Regenerate [`skills/README.md`](skills/README.md) (or just verify with `CHECK=1`). |
| `skills-doctor` | Validate every skill (frontmatter, sidecar, category) and catalog freshness. |
| `skills-update NAME=…` / `-update-all` | Re-fetch if upstream moved (category preserved). |
| `skills-delete NAME=…` | Remove a skill and its sidecar. |
| `skills-sync` / `extensions-sync` | Bulk-vendor the pi-skills set / pi-mono extensions. |
| `plugins-check` / `plugins-sync` | Diff `plugins.txt` per profile / emit the `/plugin install` lines. |

`agents-*` twins exist for every `skills-*` target (except `catalog`).
Use `SUBPATH=`, never `PATH=` — the latter clobbers the shell `PATH` inside recipes.

## Notes

- `skills/` and `pi/extensions/` are vendored — a re-sync or `skills-update` overwrites local edits; diverge intentionally and note it durably.
- Don't hand-edit `.source.json`; it's regenerated on fetch/update. Locally authored resources carry `{"repo": null}` and survive `update-all`.
- Plugin installation is manual per profile — Claude Code has no headless `/plugin install`.

## License

[Apache-2.0](LICENSE).
Vendored skills and extensions remain under their upstream licenses; see each resource's `.source.json`.
