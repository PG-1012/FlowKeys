# FlowKeys build
#
# `swift build` produces a bare executable, but a menu-bar app needs a real
# .app bundle: LSUIElement lives in Info.plist, and macOS ties Accessibility
# permission to a bundle identity.

APP      := FlowKeys.app
CONFIG   := release
BIN      := .build/$(CONFIG)/FlowKeys

.PHONY: all app run test clean install

all: app

test:
	swift test

$(BIN):
	swift build -c $(CONFIG)

app: $(BIN)
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BIN) $(APP)/Contents/MacOS/FlowKeys
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
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

clean:
	@rm -rf .build $(APP)
