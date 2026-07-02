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
│   ├── rules/             # rule files (model routing, git hygiene, delegation)
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

Shared by Claude Code and pi, grouped below by the `category` recorded in each skill's sidecar.
Most are now authored in this repo (`local`); the rest are vendored from [pi-skills](https://github.com/badlogic/pi-skills) (`brave-search`, the Google CLIs, `transcribe`, `vscode`, `youtube-transcript`), the [cursor-team-kit](https://github.com/cursor/plugins) (`deslop`, `make-pr-easy-to-review`, `pr-review-canvas`, `thermo-nuclear-code-quality-review`), and the [skills.sh](https://www.skills.sh/) ecosystem (`find-skills`, `agent-browser`, `caveman`).
Each carries a `.source.json` sidecar recording its source and a `category`; `make skills-list` prints them grouped by that category (the same groups as the tables below — Claude Code/pi only scan one level deep, so categorization is metadata, not nested folders).
To find more, `make skills-find Q=…` searches [skills.sh](https://www.skills.sh/) and `make skills-add SOURCE=owner/repo@skill CATEGORY=…` vendors the result into `skills/` (see [Makefile reference](#makefile-reference)).

The owned skills lean heavily toward maintaining a Hugo site and an OSS Go project end-to-end — authoring, CI triage, dependency hygiene, security remediation, and backlog/PR review — each one atomic so it can run alone or chain with the others.

The tables below are **generated** from the sidecars + each `SKILL.md` description — don't edit them by hand; run `make skills-catalog` after adding, removing, or recategorizing a skill (`make skills-doctor` flags a stale block).

<!-- BEGIN skills-catalog -->

**ci-go (7)**

| Skill | Purpose |
|-------|---------|
| [`analyze-go-pprof`](skills/analyze-go-pprof/SKILL.md) | Pull the heap/goroutine pprof profiles a CI job captured, separate a real leak from baseline cost, and quantify a fix's before/after delta. |
| [`analyze-prometheus-tsdb`](skills/analyze-prometheus-tsdb/SKILL.md) | Run a Prometheus TSDB snapshot that a CI job uploaded inside a local Prometheus container and query it — for before/after performance comparisons across legs... |
| [`bump-ci-tool-versions`](skills/bump-ci-tool-versions/SKILL.md) | Bump the pinned CLI tool versions that GitHub Actions workflows download at runtime (helm, kind, skaffold, cosign, golangci-lint, goreleaser, etc.) — the `*_... |
| [`debug-ci`](skills/debug-ci/SKILL.md) | Triage and root-cause a failing GitHub Actions CI run on a PR efficiently. |
| [`go-deps-security-sweep`](skills/go-deps-security-sweep/SKILL.md) | Run a grouped, bisectable Go dependency security sweep. |
| [`improve-codecov-coverage`](skills/improve-codecov-coverage/SKILL.md) | Use when raising test coverage on a Go project that reports to Codecov (triggers "improve code coverage", "cover package X", "find coverage gaps"). |
| [`watch-ci`](skills/watch-ci/SKILL.md) | After pushing to a PR, watch its CI checks to terminal state and surface each transition as a notification instead of busy-polling. |

**documents (4)**

| Skill | Purpose |
|-------|---------|
| [`docx`](skills/docx/SKILL.md) | Use this skill whenever the user wants to create, read, edit, or manipulate Word documents (.docx files). |
| [`pdf`](skills/pdf/SKILL.md) | Use this skill whenever the user wants to do anything with PDF files. |
| [`pptx`](skills/pptx/SKILL.md) | Use this skill any time a .pptx file is involved in any way — as input, output, or both. |
| [`xlsx`](skills/xlsx/SKILL.md) | Use this skill any time a spreadsheet file is the primary input or output. |

**gh-security (4)**

| Skill | Purpose |
|-------|---------|
| [`author-security-advisory`](skills/author-security-advisory/SKILL.md) | Use when triaging or preparing a GitHub repository security advisory as a maintainer (triggers "draft the advisory", "prepare GHSA content", "request CVE", "... |
| [`remediate-codeql-alerts`](skills/remediate-codeql-alerts/SKILL.md) | Use when fixing or triaging GitHub code-scanning / CodeQL alerts (triggers "fix codeql issues", "check code-scanning alerts", "dismiss false-positive alert"). |
| [`source-code-for-gh-advisory`](skills/source-code-for-gh-advisory/SKILL.md) | Use when the user wants to obtain, inspect, or reproduce the vulnerable source code referenced by a GitHub Security Advisory (GHSA-xxxx / CVE) — including se... |
| [`triage-gh-backlog`](skills/triage-gh-backlog/SKILL.md) | Use when scrubbing or triaging a GitHub repo's open issue/PR backlog — e.g. "go through all open issues and PRs and see what can be closed", "scrub the outst... |

**google-cli (3)**

| Skill | Purpose |
|-------|---------|
| [`gccli`](skills/gccli/SKILL.md) | Google Calendar CLI for listing calendars, viewing/creating/updating events, and checking availability. |
| [`gdcli`](skills/gdcli/SKILL.md) | Google Drive CLI for listing, searching, uploading, downloading, and sharing files and folders. |
| [`gmcli`](skills/gmcli/SKILL.md) | Gmail CLI for searching emails, reading threads, sending messages, managing drafts, and handling labels/attachments. |

**internal-automation (5)**

| Skill | Purpose |
|-------|---------|
| [`approve-workday-tasks`](skills/approve-workday-tasks/SKILL.md) | Use when the user wants to review and approve their pending Workday "My Tasks" approvals via the browser — invoked as /approve-workday-tasks. |
| [`fill-workday-timesheet`](skills/fill-workday-timesheet/SKILL.md) | Use when the user wants to fill in their Workday timesheet for the current week (enter hours per weekday against a project), invoked as /fill-workday-timesheet. |
| [`list-week-meetings`](skills/list-week-meetings/SKILL.md) | Use when the user wants a list of their meetings for a week from the Outlook (Microsoft 365) calendar — invoked as /list-week-meetings. |
| [`login-microsoft-sso`](skills/login-microsoft-sso/SKILL.md) | Use to ensure an authenticated browser tab for an app behind your organization's Microsoft (Entra) SSO — e.g. Workday, Engage, Outlook — via the claude-in-ch... |
| [`record-engage-activity`](skills/record-engage-activity/SKILL.md) | Use when the user wants to record an activity in Engage (the org's activity/points platform) — e.g. a billed work week or a phone interview — invoked as /rec... |

**knowledge-base (7)**

| Skill | Purpose |
|-------|---------|
| [`readwise-cli`](skills/readwise-cli/SKILL.md) | How to use the Readwise CLI — access highlights, documents, and your entire reading library from the command line |
| [`readwise-second-brain-sync`](skills/readwise-second-brain-sync/SKILL.md) | Sync Readwise highlights and Reader documents into the second-brain vault's raw/ folder in Obsidian-Web-Clipper format. |
| [`second-brain-ingest`](skills/second-brain-ingest/SKILL.md) | Process raw source documents into wiki pages. |
| [`second-brain-lint`](skills/second-brain-lint/SKILL.md) | Health-check the wiki for contradictions, orphan pages, stale claims, and missing cross-references. |
| [`second-brain-query`](skills/second-brain-query/SKILL.md) | Answer questions against the knowledge base wiki. |
| [`second-brain-review`](skills/second-brain-review/SKILL.md) | Resurface knowledge from the second-brain wiki — a daily/periodic review of highlights, concepts, and stale pages, replacing Readwise's daily review. |
| [`second-brain`](skills/second-brain/SKILL.md) | Set up a new Obsidian knowledge base with the LLM Wiki pattern. |

**meta (3)**

| Skill | Purpose |
|-------|---------|
| [`caveman`](skills/caveman/SKILL.md) | Ultra-compressed communication mode. |
| [`find-skills`](skills/find-skills/SKILL.md) | Helps users discover and install agent skills when they ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express ... |
| [`harvest-automation`](skills/harvest-automation/SKILL.md) | Use when the user wants to turn past Claude Code work into reusable automation — invoked as /harvest-automation, optionally with a window like "7d". |

**pr-review (5)**

| Skill | Purpose |
|-------|---------|
| [`deslop`](skills/deslop/SKILL.md) | Remove AI-generated code slop and clean up code style |
| [`make-pr-easy-to-review`](skills/make-pr-easy-to-review/SKILL.md) | Prepare PRs for review by cleaning noisy history, improving PR descriptions, and adding reviewer guidance without changing code behavior. |
| [`pr-review-canvas`](skills/pr-review-canvas/SKILL.md) | Generate an interactive PR review walkthrough as an HTML page. |
| [`resolve-bot-review-threads`](skills/resolve-bot-review-threads/SKILL.md) | Use when a PR has bot/Copilot review comments to clear — fix them, mark the threads resolved, and re-request the bot until the PR is at a good base (triggers... |
| [`thermo-nuclear-code-quality-review`](skills/thermo-nuclear-code-quality-review/SKILL.md) | Run an extremely strict maintainability review for abstraction quality, giant files, and spaghetti-condition growth. |

**search-media (5)**

| Skill | Purpose |
|-------|---------|
| [`agent-browser`](skills/agent-browser/SKILL.md) | Browser automation CLI for AI agents. |
| [`brave-search`](skills/brave-search/SKILL.md) | Web search and content extraction via Brave Search API. |
| [`transcribe`](skills/transcribe/SKILL.md) | Local speech-to-text transcription on Apple Silicon macOS. |
| [`vscode`](skills/vscode/SKILL.md) | VS Code integration for viewing diffs and comparing files. |
| [`youtube-transcript`](skills/youtube-transcript/SKILL.md) | Fetch transcripts from YouTube videos for summarization and analysis. |

**static-site (9)**

| Skill | Purpose |
|-------|---------|
| [`add-llms-txt`](skills/add-llms-txt/SKILL.md) | Use to add LLM-friendly outputs to a Hugo site — /llms.txt and /llms-full.txt indexes plus a per-page markdown twin at <url>/index.md — generated from conten... |
| [`audit-static-site`](skills/audit-static-site/SKILL.md) | Use to crawl a built static-site output dir and flag SEO/UX issues (titles, meta descriptions, alt text, thin/orphan/duplicate pages) before publishing. |
| [`author-mermaid-diagram`](skills/author-mermaid-diagram/SKILL.md) | Use when adding or fixing a mermaid diagram in a Hugo (or other static-site) page so it renders readably inline in a narrow content column (triggers "add a d... |
| [`bump-hugo-versions`](skills/bump-hugo-versions/SKILL.md) | Use when bumping Hugo, Go, or a theme loaded as a Hugo Module via go.mod, with versions pinned in a deploy config (netlify.toml or a GitHub Actions workflow). |
| [`generate-og-images`](skills/generate-og-images/SKILL.md) | Use to generate branded 1200x630 social-share (OG/Twitter) card images for a site's pages, with title/tags/brand overlaid by Pillow over an AI, image, or gra... |
| [`optimize-svg`](skills/optimize-svg/SKILL.md) | Use when adding or committing an SVG asset (logos, icons) to keep it small — triggers "add this logo", "optimize svg", "svg is too big". |
| [`report-site-analytics`](skills/report-site-analytics/SKILL.md) | Use to pull a GA4 + Google Search Console report (top pages, queries, CTR, near-miss positions) into a dated markdown/JSON summary for an SEO/reachability pass. |
| [`verify-hugo-build`](skills/verify-hugo-build/SKILL.md) | Use when verifying a Hugo site build before declaring it done or pushing (triggers "does it build", "verify the site", after editing layouts/SCSS/content). |
| [`write-hugo-blog-post`](skills/write-hugo-blog-post/SKILL.md) | Use when authoring or editing a blog post in a Hugo site (any theme) — triggers "write a blog post", "publish a tutorial", "add a post". |

<!-- END skills-catalog -->

### Claude commands, agents, rules, scripts

- **Command** `/history` — read the global conversation history and present it in a scannable format.
- **Agents** (each with a `.source.json` sidecar, listed by `make agents-list`):
  - `plan-reviewer` — read-only pre-execution review of an implementation plan against the actual codebase; returns APPROVE/REVISE with evidence-cited issues.
  - `bulk-mechanic` — haiku-powered executor for mechanical, judgment-free batches (renames, bumps, pattern application); the parent supplies the exact transform and file list.
  - `pr-shepherd` — drives the push → CI → bot-review loop to green via the `watch-ci` / `debug-ci` / `resolve-bot-review-threads` skills; never opens or merges PRs itself.
  - `skill-auditor` — read-only audit of a skill directory against the repo's conventions (atomic scope, trigger-rich description, sidecar + category, no PII).
  - `thermo-nuclear-code-quality-review` — strict maintainability audit (1k-line rule, spaghetti, code-judo), driven by the matching skill; vendored from the cursor-team-kit.
- **Rules** (`claude/rules/`, loaded in every session in both profiles):
  - `model-routing.md` — route tasks to the cheapest reliable model tier (haiku mechanical / sonnet routine / session model for judgment) and calibrate effort.
  - `git-hygiene.md` — staging, commit, and push discipline.
  - `delegation.md` — when to hand work to the subagents above instead of doing it inline.
- **Scripts** — `md-one-sentence-per-line.py` (the markdown formatter the shared `CLAUDE.md` points at) and `statusline-command.sh` (a `statusLine` hook script: `[model] folder | branch · context bar · $cost · elapsed`).

### Shared `CLAUDE.md`

Profile-agnostic global instructions applied to both Claude accounts:

- Never publish secrets; never commit `.env`.
- A pointer to the `claude/rules/` files above, so every session knows they exist.
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
| `skills-catalog [CHECK=1]` | Regenerate the category-grouped skill tables in this README (or just verify with `CHECK=1`). |
| `skills-doctor` / `agents-doctor` | Validate every resource (frontmatter, sidecar, category) and, for skills, that the README catalog is current. |
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
