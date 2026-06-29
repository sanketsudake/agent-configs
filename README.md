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
  Each skill/agent carries a `.source.json` sidecar recording its origin repo, subpath, ref, and resolved commit, so a vendored one can be updated later with one command — vendoring without losing provenance, and locally-authored ones are marked too.
- **Guardrail extensions for pi.**
  Confirm-before-destructive, dirty-repo guard, protected paths, and a permission gate run as agent extensions, not as hope.
- **Desired-state plugins.**
  `plugins.txt` is the declared plugin set; `make plugins-check` reports drift per profile.
- **Borrow a popular CLI's discovery without adopting its model.**
  `make skills-find` / `skills-add` front the [`skills`](https://github.com/vercel-labs/skills) CLI (the skills.sh ecosystem) for discovery and fetching, but pipe the result back into the repo's own vendoring + `.source.json` tracking — so the dual profiles, subagent management, and committed/offline skills all survive.

## Layout

```
harness-configs/
├── Makefile               # primary interface — all <resource>-<action> targets
├── CLAUDE.md              # guide for agents working IN this repo
├── LICENSE                # Apache-2.0
├── claude/                # Claude Code config, symlinked into both profiles
│   ├── CLAUDE.md          # shared global user instructions (both profiles)
│   ├── commands/          # slash commands
│   ├── agents/            # subagents (+ .source.json sidecars)
│   ├── rules/             # rule files (currently just a .gitkeep)
│   ├── scripts/           # helper scripts (md formatter, statusline hook)
│   └── plugins.txt        # desired-state plugin list
├── skills/                # shared skills for Claude + pi (source of truth)
│   └── <name>/SKILL.md    # each with a .source.json sidecar
├── pi/                    # pi agent config, stowed into ~/.pi
│   ├── agent/settings.json
│   ├── prompts/
│   └── extensions/        # TypeScript extensions (+ subagent/ dir extension)
└── scripts/               # repo tooling (not symlinked into profiles)
    ├── resource-manager.sh    # fetch/track/update skills & agents
    ├── skills-vendor.sh       # skills.sh discovery/fetch → vendored into skills/
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

Shared by Claude Code and pi — 36 of them, grouped below.
Most are now authored in this repo (`local`); the rest are vendored from [pi-skills](https://github.com/badlogic/pi-skills) (`brave-search`, the Google CLIs, `transcribe`, `vscode`, `youtube-transcript`), the [cursor-team-kit](https://github.com/cursor/plugins) (`deslop`, `make-pr-easy-to-review`, `pr-review-canvas`, `thermo-nuclear-code-quality-review`), and the [skills.sh](https://www.skills.sh/) ecosystem (`find-skills`, `agent-browser`, `caveman`).
Each carries a `.source.json` sidecar recording its source and a `category`; `make skills-list` prints them grouped by that category (the same domains as the tables below — Claude Code/pi only scan one level deep, so categorization is metadata, not nested folders).
To find more, `make skills-find Q=…` searches [skills.sh](https://www.skills.sh/) and `make skills-add SOURCE=owner/repo@skill CATEGORY=…` vendors the result into `skills/` (see [Makefile reference](#makefile-reference)).

The owned skills lean heavily toward maintaining a Hugo site and an OSS Go project end-to-end — authoring, CI triage, dependency hygiene, security remediation, and backlog/PR review — each one atomic so it can run alone or chain with the others.

**Hugo / static-site authoring & SEO**

| Skill | Purpose |
|-------|---------|
| `write-hugo-blog-post` | Author/edit a Hugo post: file layout, front matter, featured-image → card+OG flow. |
| `author-mermaid-diagram` | Add a mermaid diagram that renders readably in a narrow content column. |
| `generate-og-images` | Render branded 1200×630 social-share cards over an AI/image/gradient background. |
| `optimize-svg` | Shrink an SVG asset with svgo, keeping the result only if it actually got smaller. |
| `add-llms-txt` | Add `/llms.txt`, `/llms-full.txt`, and per-page markdown twins, generated from content. |
| `audit-static-site` | Crawl built HTML and flag SEO/UX issues (titles, meta, alt text, thin/orphan pages). |
| `report-site-analytics` | Pull a dated GA4 + Search Console report (top pages, queries, CTR, near-misses). |
| `verify-hugo-build` | Build the site the way the host runs it before declaring it done. |
| `bump-hugo-versions` | Bump Hugo/Go/theme versions pinned in a deploy config (netlify.toml / Actions). |

**CI, Go & dependencies**

| Skill | Purpose |
|-------|---------|
| `debug-ci` | Triage and root-cause a failing GitHub Actions run, cheapest log fetch first. |
| `watch-ci` | Watch a PR's checks to terminal state, surfacing each transition as a notification. |
| `analyze-go-pprof` | Pull CI-captured heap/goroutine profiles; separate a real leak from baseline cost. |
| `analyze-prometheus-tsdb` | Query a CI-uploaded Prometheus TSDB snapshot for over-the-run time series. |
| `go-deps-security-sweep` | Grouped, bisectable Go dependency upgrade — one commit per logical group. |
| `improve-codecov-coverage` | Rank low-covered Go packages, write targeted tests, verify the delta. |
| `bump-ci-tool-versions` | Bump runtime-downloaded CLI versions (helm, kind, skaffold, cosign, …) in workflows. |

**PR review & code quality**

| Skill | Purpose |
|-------|---------|
| `make-pr-easy-to-review` | Clean noisy history, improve PR descriptions, and annotate diffs without changing behavior. |
| `pr-review-canvas` | Generate an interactive HTML PR-review walkthrough from `gh` API data. |
| `resolve-bot-review-threads` | Fix bot/Copilot comments, resolve the threads, and re-request review. |
| `thermo-nuclear-code-quality-review` | Extremely strict maintainability review (abstraction, giant files, spaghetti). |
| `deslop` | Remove AI-generated code slop and clean up code style. |

**GitHub security & maintenance**

| Skill | Purpose |
|-------|---------|
| `triage-gh-backlog` | Scrub an open issue/PR backlog like a PM, backed by a local SQLite mirror. |
| `author-security-advisory` | Triage/draft a repo security advisory and produce paste-ready GHSA content. |
| `remediate-codeql-alerts` | Fix or dismiss code-scanning/CodeQL alerts and verify on the merge ref. |
| `source-code-for-gh-advisory` | Obtain and reproduce the vulnerable source referenced by a GHSA/CVE. |

**Search, media & desktop**

| Skill | Purpose |
|-------|---------|
| `brave-search` | Web search and content extraction via the Brave Search API; no browser needed. |
| `agent-browser` | Browser/Electron automation CLI for agents (CDP, accessibility-tree snapshots); needs `npm i -g agent-browser`. |
| `youtube-transcript` | Fetch YouTube transcripts for summarization and analysis. |
| `transcribe` | Local speech-to-text on Apple Silicon macOS. |
| `vscode` | VS Code integration for viewing diffs and comparing files. |

**Google Workspace CLIs**

| Skill | Purpose |
|-------|---------|
| `gccli` | Google Calendar CLI: list calendars, view/create/update events, check availability. |
| `gdcli` | Google Drive CLI: list, search, upload, download, and share files and folders. |
| `gmcli` | Gmail CLI: search, read threads, send, manage drafts, labels, and attachments. |

**Meta**

| Skill | Purpose |
|-------|---------|
| `harvest-automation` | Mine past Claude Code sessions and turn recurring patterns into skills, CLAUDE.md entries, and memory. |
| `find-skills` | Discover and install skills from the skills.sh ecosystem on request. |
| `caveman` | Ultra-compressed "caveman" response mode that cuts token use while keeping technical accuracy. |

### Claude commands, agents, rules, scripts

- **Command** `/history` — read the global conversation history and present it in a scannable format.
- **Agent** `thermo-nuclear-code-quality-review` — strict maintainability audit (1k-line rule, spaghetti, code-judo), driven by the matching skill; vendored from the cursor-team-kit with a `.source.json` sidecar.
- **Rules** — `claude/rules/` is wired up for rule files (currently just a `.gitkeep`).
- **Scripts** — `md-one-sentence-per-line.py` (the markdown formatter the shared `CLAUDE.md` points at) and `statusline-command.sh` (a `statusLine` hook script: `[model] folder | branch · context bar · $cost · elapsed`).

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
`gh` is needed only for the GitHub-facing skills; `python3` for the markdown formatter and the Python-backed skills (`generate-og-images`, `report-site-analytics`, `transcribe`, …); `npx` (Node.js) only for the `skills-find` / `skills-add` discovery targets.
Individual skills declare their own extra tools (svgo, hugo, the Brave API key, etc.) in their `SKILL.md`.

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
| `skills-find [Q=… OWNER=…]` | Discover skills on [skills.sh](https://www.skills.sh/) via the `skills` CLI; prints `owner/repo@skill` hits. |
| `skills-add SOURCE=… [SKILL=… CATEGORY=…]` | Fetch from skills.sh/GitHub via the `skills` CLI and vendor into `skills/` with a `.source.json` (optionally tagged `CATEGORY=`). |
| `skills-fetch REPO=… SUBPATH=… [CATEGORY=…]` | Fetch one skill from any repo/subpath and write its `.source.json`. |
| `agents-fetch REPO=… SUBPATH=…` | Same, for a single agent `.md` file. |
| `skills-list` / `agents-list` | Every resource with status (`remote`/`local`/`unmanaged`) and source, **grouped by category**. |
| `skills-category NAME=… CATEGORY=…` | Set/replace a resource's category (survives `skills-update`). |
| `skills-update NAME=…` / `-update-all` | Re-resolve the recorded ref and re-copy if upstream moved (category preserved). |
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

## License

[Apache-2.0](LICENSE).
Vendored skills and extensions remain under their upstream licenses; see each resource's `.source.json` for its origin.
