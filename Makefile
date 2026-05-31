PKG_NAME := gridtilio
ARCHIVE  := $(PKG_NAME).kwinscript

SOURCES  := metadata.json $(shell find contents -type f)

.PHONY: build install update uninstall reconfigure clean help

help:
	@echo "make build       - build $(ARCHIVE) from metadata.json + contents/"
	@echo "make install     - build, install, enable in kwinrc, reconfigure KWin"
	@echo "make update      - alias for install (kpackagetool6 -u upgrades if present)"
	@echo "make uninstall   - disable in kwinrc, uninstall, reconfigure KWin"
	@echo "make reconfigure - ask KWin to reread kwinrc"
	@echo "make clean       - remove $(ARCHIVE)"

build: $(ARCHIVE)

$(ARCHIVE): $(SOURCES)
	@rm -f $@
	zip -rq $@ metadata.json contents/

install: $(ARCHIVE)
	kpackagetool6 --type=KWin/Script -i $(ARCHIVE) 2>/dev/null \
	  || kpackagetool6 --type=KWin/Script -u $(ARCHIVE)
	kwriteconfig6 --file kwinrc --group Plugins --key $(PKG_NAME)Enabled true
	$(MAKE) --no-print-directory reconfigure
	@echo
	@echo "Installed. Press Meta+Return on any window to open the overlay."
	@echo "Rebind the shortcut in System Settings -> Shortcuts -> KWin."

update: install

uninstall:
	-kwriteconfig6 --file kwinrc --group Plugins --key $(PKG_NAME)Enabled --delete
	-kpackagetool6 --type=KWin/Script -r $(PKG_NAME)
	$(MAKE) --no-print-directory reconfigure

reconfigure:
	dbus-send --session --type=method_call \
	  --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure

clean:
	rm -f $(ARCHIVE)
