STOW := stow
STOW_DIR := $(CURDIR)
PI_TARGET := $(HOME)/.pi

PI_SKILLS_REPO := https://github.com/badlogic/pi-skills
PI_SKILLS_CACHE := /tmp/pi-skills
PI_SKILLS_DIR := $(CURDIR)/skills

CLAUDE_CONFIG_DIRS := $(HOME)/.claude-personal $(HOME)/.claude-work
SKILL_LINK_TARGETS := $(PI_TARGET) $(CLAUDE_CONFIG_DIRS)

CLAUDE_DIR := $(CURDIR)/claude
PLUGINS_FILE := $(CLAUDE_DIR)/plugins.txt
CLAUDE_MD_FILE := $(CLAUDE_DIR)/CLAUDE.md
COMMANDS_DIR := $(CLAUDE_DIR)/commands
RULES_DIR := $(CLAUDE_DIR)/rules
SCRIPTS_DIR := $(CLAUDE_DIR)/scripts
AGENTS_DIR := $(CLAUDE_DIR)/agents

RESOURCE_MANAGER := $(CURDIR)/scripts/resource-manager.sh
SKILLS_VENDOR := $(CURDIR)/scripts/skills-vendor.sh

PI_MONO_REPO := https://github.com/badlogic/pi-mono
PI_MONO_CACHE := /tmp/pi-mono
PI_MONO_EXTENSIONS_SRC := $(PI_MONO_CACHE)/packages/coding-agent/examples/extensions
PI_EXTENSIONS_DIR := $(CURDIR)/pi/extensions

PI_EXTENSIONS := \
	confirm-destructive.ts \
	dirty-repo-guard.ts \
	mac-system-theme.ts \
	permission-gate.ts \
	protected-paths.ts \
	status-line.ts \
	todo.ts \
	notify.ts \
	handoff.ts \
	subagent

SHELL := /bin/bash

.PHONY: install uninstall \
	skills-link skills-unlink claude-md-link claude-md-unlink \
	commands-link commands-unlink rules-link rules-unlink scripts-link scripts-unlink \
	agents-link agents-unlink \
	skills-sync extensions-sync plugins-check plugins-sync \
	skills-find skills-add \
	skills-fetch skills-list skills-update skills-update-all skills-category skills-delete \
	agents-fetch agents-list agents-update agents-update-all agents-category agents-delete

install: skills-link claude-md-link commands-link rules-link scripts-link agents-link
	mkdir -p $(PI_TARGET)
	$(STOW) --dir=$(STOW_DIR) --target=$(PI_TARGET) --adopt pi

uninstall: skills-unlink claude-md-unlink commands-unlink rules-unlink scripts-unlink agents-unlink
	$(STOW) --dir=$(STOW_DIR) --target=$(PI_TARGET) --delete pi

skills-link:
	mkdir -p $(PI_SKILLS_DIR)
	for target in $(SKILL_LINK_TARGETS); do \
		mkdir -p $$target; \
		link=$$target/skills; \
		if [ -L $$link ]; then \
			rm $$link; \
		elif [ -d $$link ]; then \
			rmdir $$link 2>/dev/null || { echo "skip: $$link is a non-empty directory"; continue; }; \
		fi; \
		ln -s $(PI_SKILLS_DIR) $$link; \
		echo "linked: $$link -> $(PI_SKILLS_DIR)"; \
	done

skills-unlink:
	for target in $(SKILL_LINK_TARGETS); do \
		link=$$target/skills; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(PI_SKILLS_DIR)" ]; then \
			rm $$link; \
			echo "unlinked: $$link"; \
		fi; \
	done

claude-md-link:
	@test -f $(CLAUDE_MD_FILE) || { echo "missing: $(CLAUDE_MD_FILE)"; exit 1; }
	for target in $(CLAUDE_CONFIG_DIRS); do \
		mkdir -p $$target; \
		link=$$target/CLAUDE.md; \
		if [ -L $$link ]; then \
			rm $$link; \
		elif [ -f $$link ]; then \
			backup=$$link.bak.$$(date +%Y%m%d%H%M%S); \
			mv $$link $$backup; \
			echo "backed up: $$link -> $$backup"; \
		fi; \
		ln -s $(CLAUDE_MD_FILE) $$link; \
		echo "linked: $$link -> $(CLAUDE_MD_FILE)"; \
	done

claude-md-unlink:
	for target in $(CLAUDE_CONFIG_DIRS); do \
		link=$$target/CLAUDE.md; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(CLAUDE_MD_FILE)" ]; then \
			rm $$link; \
			echo "unlinked: $$link"; \
		fi; \
	done

commands-link:
	mkdir -p $(COMMANDS_DIR)
	for target in $(CLAUDE_CONFIG_DIRS); do \
		mkdir -p $$target; \
		link=$$target/commands; \
		if [ -L $$link ]; then \
			rm $$link; \
		elif [ -d $$link ]; then \
			rmdir $$link 2>/dev/null || { echo "skip: $$link is a non-empty directory"; continue; }; \
		fi; \
		ln -s $(COMMANDS_DIR) $$link; \
		echo "linked: $$link -> $(COMMANDS_DIR)"; \
	done

commands-unlink:
	for target in $(CLAUDE_CONFIG_DIRS); do \
		link=$$target/commands; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(COMMANDS_DIR)" ]; then \
			rm $$link; \
			echo "unlinked: $$link"; \
		fi; \
	done

rules-link:
	mkdir -p $(RULES_DIR)
	for target in $(CLAUDE_CONFIG_DIRS); do \
		mkdir -p $$target; \
		link=$$target/rules; \
		if [ -L $$link ]; then \
			rm $$link; \
		elif [ -d $$link ]; then \
			rmdir $$link 2>/dev/null || { echo "skip: $$link is a non-empty directory"; continue; }; \
		fi; \
		ln -s $(RULES_DIR) $$link; \
		echo "linked: $$link -> $(RULES_DIR)"; \
	done

rules-unlink:
	for target in $(CLAUDE_CONFIG_DIRS); do \
		link=$$target/rules; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(RULES_DIR)" ]; then \
			rm $$link; \
			echo "unlinked: $$link"; \
		fi; \
	done

scripts-link:
	mkdir -p $(SCRIPTS_DIR)
	for target in $(CLAUDE_CONFIG_DIRS); do \
		mkdir -p $$target; \
		link=$$target/scripts; \
		if [ -L $$link ]; then \
			rm $$link; \
		elif [ -d $$link ]; then \
			rmdir $$link 2>/dev/null || { echo "skip: $$link is a non-empty directory"; continue; }; \
		fi; \
		ln -s $(SCRIPTS_DIR) $$link; \
		echo "linked: $$link -> $(SCRIPTS_DIR)"; \
	done

scripts-unlink:
	for target in $(CLAUDE_CONFIG_DIRS); do \
		link=$$target/scripts; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(SCRIPTS_DIR)" ]; then \
			rm $$link; \
			echo "unlinked: $$link"; \
		fi; \
	done

agents-link:
	mkdir -p $(AGENTS_DIR)
	for target in $(CLAUDE_CONFIG_DIRS); do \
		mkdir -p $$target; \
		link=$$target/agents; \
		if [ -L $$link ]; then \
			rm $$link; \
		elif [ -d $$link ]; then \
			rmdir $$link 2>/dev/null || { echo "skip: $$link is a non-empty directory"; continue; }; \
		fi; \
		ln -s $(AGENTS_DIR) $$link; \
		echo "linked: $$link -> $(AGENTS_DIR)"; \
	done

agents-unlink:
	for target in $(CLAUDE_CONFIG_DIRS); do \
		link=$$target/agents; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(AGENTS_DIR)" ]; then \
			rm $$link; \
			echo "unlinked: $$link"; \
		fi; \
	done

plugins-check:
	@test -f $(PLUGINS_FILE) || { echo "missing: $(PLUGINS_FILE)"; exit 1; }
	@command -v jq >/dev/null || { echo "jq required"; exit 1; }
	@desired=$$(grep -v '^[[:space:]]*#' $(PLUGINS_FILE) | grep -v '^[[:space:]]*$$' | sort -u); \
	for target in $(CLAUDE_CONFIG_DIRS); do \
		echo "== $$target =="; \
		file=$$target/plugins/installed_plugins.json; \
		if [ ! -f $$file ]; then \
			echo "  no installed_plugins.json"; \
			continue; \
		fi; \
		installed=$$(jq -r '.plugins | to_entries[] | select(.value | map(.scope) | index("user")) | .key' $$file | sort -u); \
		missing=$$(comm -23 <(echo "$$desired") <(echo "$$installed")); \
		extra=$$(comm -13 <(echo "$$desired") <(echo "$$installed")); \
		if [ -n "$$missing" ]; then \
			echo "  missing (run /plugin install <name> in this profile):"; \
			echo "$$missing" | sed 's/^/    /'; \
		fi; \
		if [ -n "$$extra" ]; then \
			echo "  extra (user-scoped, not in plugins.txt):"; \
			echo "$$extra" | sed 's/^/    /'; \
		fi; \
		if [ -z "$$missing" ] && [ -z "$$extra" ]; then \
			echo "  in sync"; \
		fi; \
	done

plugins-sync:
	@test -f $(PLUGINS_FILE) || { echo "missing: $(PLUGINS_FILE)"; exit 1; }
	@command -v jq >/dev/null || { echo "jq required"; exit 1; }
	@desired=$$(grep -v '^[[:space:]]*#' $(PLUGINS_FILE) | grep -v '^[[:space:]]*$$' | sort -u); \
	for target in $(CLAUDE_CONFIG_DIRS); do \
		case $$target in \
			*personal*) wrap=pclaude ;; \
			*work*)     wrap=wclaude ;; \
			*)          wrap="claude (with CLAUDE_CONFIG_DIR=$$target)" ;; \
		esac; \
		echo "== $$target =="; \
		file=$$target/plugins/installed_plugins.json; \
		if [ ! -f $$file ]; then \
			installed=""; \
		else \
			installed=$$(jq -r '.plugins | to_entries[] | select(.value | map(.scope) | index("user")) | .key' $$file | sort -u); \
		fi; \
		missing=$$(comm -23 <(echo "$$desired") <(echo "$$installed")); \
		if [ -z "$$missing" ]; then \
			echo "  in sync"; \
			continue; \
		fi; \
		echo "  Start a session with \`$$wrap\` and paste:"; \
		echo "$$missing" | sed 's|^|    /plugin install |'; \
	done

skills-sync:
	if [ -d $(PI_SKILLS_CACHE)/.git ]; then \
		git -C $(PI_SKILLS_CACHE) pull --ff-only; \
	else \
		git clone --depth=1 $(PI_SKILLS_REPO) $(PI_SKILLS_CACHE); \
	fi
	mkdir -p $(PI_SKILLS_DIR)
	for dir in $$(find $(PI_SKILLS_CACHE) -mindepth 1 -maxdepth 1 -type d ! -name '.git'); do \
		cp -r $$dir $(PI_SKILLS_DIR)/; \
	done

extensions-sync:
	if [ -d $(PI_MONO_CACHE)/.git ]; then \
		git -C $(PI_MONO_CACHE) pull --ff-only; \
	else \
		git clone --depth=1 $(PI_MONO_REPO) $(PI_MONO_CACHE); \
	fi
	mkdir -p $(PI_EXTENSIONS_DIR)
	for ext in $(PI_EXTENSIONS); do \
		cp -r $(PI_MONO_EXTENSIONS_SRC)/$$ext $(PI_EXTENSIONS_DIR)/; \
	done

# --- skills.sh discovery + fetch (scripts/skills-vendor.sh) ----------------
# Front-end onto the vercel-labs `skills` CLI (npx skills, the skills.sh
# ecosystem). skills-find discovers; skills-add fetches via the CLI and vendors
# the result into skills/ through resource-manager.sh, so each lands with a
# .source.json and stays manageable by skills-list / skills-update / skills-delete.
# The CLI is used only as a resolver/fetcher — it never installs per-agent, so
# the two Claude profiles and claude/agents/ subagents are unaffected.
# Set GITHUB_TOKEN (or have `gh` logged in) to avoid anonymous rate limits.

skills-find:
	@command -v npx >/dev/null || { echo "npx (Node.js) required"; exit 1; }
	npx -y skills@latest find $(if $(Q),"$(Q)") $(if $(OWNER),--owner "$(OWNER)")

skills-add:
	@test -n "$(SOURCE)" || { echo "usage: make skills-add SOURCE=owner/repo [SKILL='a b'] [ALL=1] [REF=main] [FORCE=1]"; exit 1; }
	@$(SKILLS_VENDOR) --source "$(SOURCE)" \
		$(if $(SKILL),--skill "$(SKILL)") \
		$(if $(ALL),--all) \
		$(if $(REF),--ref "$(REF)") \
		$(if $(CATEGORY),--category "$(CATEGORY)") \
		$(if $(FORCE),--force)

# --- Source management (scripts/resource-manager.sh) -----------------------
# Fetch one skill (dir under skills/) or agent (.md under claude/agents/) from
# any repo/subpath, tracking its source in a .source.json sidecar so it can be
# listed, updated, and deleted.

skills-fetch:
	@$(RESOURCE_MANAGER) --kind skill fetch \
		$(if $(URL),--url "$(URL)") \
		$(if $(REPO),--repo "$(REPO)") \
		$(if $(SUBPATH),--subpath "$(SUBPATH)") \
		$(if $(REF),--ref "$(REF)") \
		$(if $(NAME),--name "$(NAME)") \
		$(if $(CATEGORY),--category "$(CATEGORY)") \
		$(if $(FORCE),--force)

skills-list:
	@$(RESOURCE_MANAGER) --kind skill list

skills-update:
	@$(RESOURCE_MANAGER) --kind skill update --name "$(NAME)"

skills-update-all:
	@$(RESOURCE_MANAGER) --kind skill update --all

skills-category:
	@test -n "$(NAME)" -a -n "$(CATEGORY)" || { echo "usage: make skills-category NAME=<skill> CATEGORY=<category>"; exit 1; }
	@$(RESOURCE_MANAGER) --kind skill category --name "$(NAME)" --category "$(CATEGORY)"

skills-delete:
	@$(RESOURCE_MANAGER) --kind skill delete --name "$(NAME)" $(if $(YES),--yes)

agents-fetch:
	@$(RESOURCE_MANAGER) --kind agent fetch \
		$(if $(URL),--url "$(URL)") \
		$(if $(REPO),--repo "$(REPO)") \
		$(if $(SUBPATH),--subpath "$(SUBPATH)") \
		$(if $(REF),--ref "$(REF)") \
		$(if $(NAME),--name "$(NAME)") \
		$(if $(CATEGORY),--category "$(CATEGORY)") \
		$(if $(FORCE),--force)

agents-list:
	@$(RESOURCE_MANAGER) --kind agent list

agents-update:
	@$(RESOURCE_MANAGER) --kind agent update --name "$(NAME)"

agents-update-all:
	@$(RESOURCE_MANAGER) --kind agent update --all

agents-category:
	@test -n "$(NAME)" -a -n "$(CATEGORY)" || { echo "usage: make agents-category NAME=<agent> CATEGORY=<category>"; exit 1; }
	@$(RESOURCE_MANAGER) --kind agent category --name "$(NAME)" --category "$(CATEGORY)"

agents-delete:
	@$(RESOURCE_MANAGER) --kind agent delete --name "$(NAME)" $(if $(YES),--yes)
