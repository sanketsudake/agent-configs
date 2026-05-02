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

.PHONY: install uninstall sync-skills sync-extensions link-skills unlink-skills link-claude-md unlink-claude-md link-commands unlink-commands link-rules unlink-rules link-scripts unlink-scripts plugins-check

install: link-skills link-claude-md link-commands link-rules link-scripts
	mkdir -p $(PI_TARGET)
	$(STOW) --dir=$(STOW_DIR) --target=$(PI_TARGET) --adopt pi

uninstall: unlink-skills unlink-claude-md unlink-commands unlink-rules unlink-scripts
	$(STOW) --dir=$(STOW_DIR) --target=$(PI_TARGET) --delete pi

link-skills:
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

unlink-skills:
	for target in $(SKILL_LINK_TARGETS); do \
		link=$$target/skills; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(PI_SKILLS_DIR)" ]; then \
			rm $$link; \
			echo "unlinked: $$link"; \
		fi; \
	done

link-claude-md:
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

unlink-claude-md:
	for target in $(CLAUDE_CONFIG_DIRS); do \
		link=$$target/CLAUDE.md; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(CLAUDE_MD_FILE)" ]; then \
			rm $$link; \
			echo "unlinked: $$link"; \
		fi; \
	done

link-commands:
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

unlink-commands:
	for target in $(CLAUDE_CONFIG_DIRS); do \
		link=$$target/commands; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(COMMANDS_DIR)" ]; then \
			rm $$link; \
			echo "unlinked: $$link"; \
		fi; \
	done

link-rules:
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

unlink-rules:
	for target in $(CLAUDE_CONFIG_DIRS); do \
		link=$$target/rules; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(RULES_DIR)" ]; then \
			rm $$link; \
			echo "unlinked: $$link"; \
		fi; \
	done

link-scripts:
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

unlink-scripts:
	for target in $(CLAUDE_CONFIG_DIRS); do \
		link=$$target/scripts; \
		if [ -L $$link ] && [ "$$(readlink $$link)" = "$(SCRIPTS_DIR)" ]; then \
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

sync-skills:
	if [ -d $(PI_SKILLS_CACHE)/.git ]; then \
		git -C $(PI_SKILLS_CACHE) pull --ff-only; \
	else \
		git clone --depth=1 $(PI_SKILLS_REPO) $(PI_SKILLS_CACHE); \
	fi
	mkdir -p $(PI_SKILLS_DIR)
	for dir in $$(find $(PI_SKILLS_CACHE) -mindepth 1 -maxdepth 1 -type d ! -name '.git'); do \
		cp -r $$dir $(PI_SKILLS_DIR)/; \
	done

sync-extensions:
	if [ -d $(PI_MONO_CACHE)/.git ]; then \
		git -C $(PI_MONO_CACHE) pull --ff-only; \
	else \
		git clone --depth=1 $(PI_MONO_REPO) $(PI_MONO_CACHE); \
	fi
	mkdir -p $(PI_EXTENSIONS_DIR)
	for ext in $(PI_EXTENSIONS); do \
		cp -r $(PI_MONO_EXTENSIONS_SRC)/$$ext $(PI_EXTENSIONS_DIR)/; \
	done
