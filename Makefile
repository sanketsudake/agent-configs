STOW := stow
STOW_DIR := $(CURDIR)
PI_TARGET := $(HOME)/.pi

PI_SKILLS_REPO := https://github.com/badlogic/pi-skills
PI_SKILLS_CACHE := /tmp/pi-skills
PI_SKILLS_DIR := $(CURDIR)/pi/skills

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
	subagent

.PHONY: install uninstall sync-skills sync-extensions

install:
	mkdir -p $(PI_TARGET)
	$(STOW) --dir=$(STOW_DIR) --target=$(PI_TARGET) --adopt pi

uninstall:
	$(STOW) --dir=$(STOW_DIR) --target=$(PI_TARGET) --delete pi

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
