STOW := stow
STOW_DIR := $(CURDIR)
PI_TARGET := $(HOME)/.pi

PI_SKILLS_REPO := https://github.com/badlogic/pi-skills
PI_SKILLS_CACHE := /tmp/pi-skills
PI_SKILLS_DIR := $(CURDIR)/pi/skills

.PHONY: install uninstall sync-skills

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
