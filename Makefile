# FlowKeys build
#
# `swift build` produces a bare executable, but a menu-bar app needs a real
# .app bundle: LSUIElement lives in Info.plist, and macOS ties Accessibility
# permission to a bundle identity.

APP      := FlowKeys.app
CONFIG   := release
BIN      := .build/$(CONFIG)/FlowKeys

# Ad-hoc by default. macOS keys Accessibility permission to the signature, so
# an ad-hoc build has to be re-granted after every rebuild. Pass a stable
# self-signed identity to avoid that:
#   make install SIGN_IDENTITY="FlowKeys Local Signing"
SIGN_IDENTITY ?= -

.PHONY: all build app run test clean install reset-permission icon

all: app

test:
	swift test

# Always delegate to swift build rather than treating $(BIN) as an up-to-date
# file target. A bare `$(BIN):` rule with no prerequisites makes `make` skip
# the compile whenever the binary already exists, which silently ships a stale
# binary on every subsequent `make app` / `make install`. swift build is
# incremental, so running it unconditionally costs nothing.
build:
	@swift build -c $(CONFIG)

icon:
	@python3 Tools/make_icon.py Resources/FlowKeys.icns

app: build
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BIN) $(APP)/Contents/MacOS/FlowKeys
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
	@cp Resources/FlowKeys.icns $(APP)/Contents/Resources/FlowKeys.icns
	@# Ad-hoc signature. Accessibility permission is keyed to this identity,
	@# so a rebuild that changes it means re-granting permission once.
	@codesign --force --deep --sign $(SIGN_IDENTITY) $(APP)
	@echo "Built $(APP)  (binary $$(stat -f '%Sm' $(APP)/Contents/MacOS/FlowKeys))"

run: app
	@open $(APP)

install: app
	@rm -rf /Applications/$(APP)
	@cp -R $(APP) /Applications/
	@echo "Installed to /Applications/$(APP)"
	@# Guard against shipping a stale binary again: the installed copy must
	@# match the one just built.
	@cmp -s $(APP)/Contents/MacOS/FlowKeys /Applications/$(APP)/Contents/MacOS/FlowKeys \
		&& echo "Verified: installed binary matches the build." \
		|| (echo "MISMATCH: install did not take effect" && exit 1)

# An ad-hoc signature changes on every rebuild, and macOS keys Accessibility
# permission to it -- so a rebuild orphans the old grant and leaves a stale
# duplicate entry in System Settings. Clear both, then re-grant once.
reset-permission:
	@tccutil reset Accessibility com.pg1012.FlowKeys
	@echo "Cleared. Relaunch FlowKeys and grant access again."

clean:
	@rm -rf .build $(APP)
