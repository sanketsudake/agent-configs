STOW := stow
STOW_DIR := $(CURDIR)
PI_TARGET := $(HOME)/.pi

.PHONY: install uninstall

install:
	mkdir -p $(PI_TARGET)
	$(STOW) --dir=$(STOW_DIR) --target=$(PI_TARGET) --adopt pi

uninstall:
	$(STOW) --dir=$(STOW_DIR) --target=$(PI_TARGET) --delete pi
