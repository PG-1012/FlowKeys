# FlowKeys build
#
# `swift build` produces a bare executable, but a menu-bar app needs a real
# .app bundle: LSUIElement lives in Info.plist, and macOS ties Accessibility
# permission to a bundle identity.

APP      := FlowKeys.app
CONFIG   := release
BIN      := .build/$(CONFIG)/FlowKeys

.PHONY: all app run test clean install reset-permission icon

all: app

test:
	swift test

$(BIN):
	swift build -c $(CONFIG)

icon:
	@python3 Tools/make_icon.py Resources/FlowKeys.icns

app: $(BIN)
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BIN) $(APP)/Contents/MacOS/FlowKeys
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
	@cp Resources/FlowKeys.icns $(APP)/Contents/Resources/FlowKeys.icns
	@# Ad-hoc signature. Accessibility permission is keyed to this identity,
	@# so a rebuild that changes it means re-granting permission once.
	@codesign --force --deep --sign - $(APP)
	@echo "Built $(APP)"

run: app
	@open $(APP)

install: app
	@rm -rf /Applications/$(APP)
	@cp -R $(APP) /Applications/
	@echo "Installed to /Applications/$(APP)"

# An ad-hoc signature changes on every rebuild, and macOS keys Accessibility
# permission to it -- so a rebuild orphans the old grant and leaves a stale
# duplicate entry in System Settings. Clear both, then re-grant once.
reset-permission:
	@tccutil reset Accessibility com.pg1012.FlowKeys
	@echo "Cleared. Relaunch FlowKeys and grant access again."

clean:
	@rm -rf .build $(APP)
