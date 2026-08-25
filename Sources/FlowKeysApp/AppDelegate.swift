import Cocoa
import FlowKeysCore
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var preferences = Preferences.load()
    /// Items currently shown in the overlay: the whole history, or whatever
    /// survives the type-to-filter query.
    private var visibleItems: [ClipboardItem] = []
    private var settingsWindow: NSWindow?
    private var store: ClipboardStore!
    private var watcher: ClipboardWatcher!
    private var eventTap: EventTap!
    private var pasteEngine: PasteEngine!
    private let overlay = OverlayPanel()
    private var session = CycleSession()

    private var statusItem: NSStatusItem?
    private var revealTimer: Timer?
    private var permissionTimer: Timer?
    private var commandHeld = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu-bar only: no Dock icon, never becomes the active app.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ClipboardStore(
            capacity: preferences.historyCapacity,
            persistenceURL: preferences.persistHistory ? Preferences.storageURL : nil,
            forgetAfter: preferences.forgetAfter
        )
        pasteEngine = PasteEngine(restoreClipboard: preferences.restoreClipboardAfterPaste)

        watcher = ClipboardWatcher(store: store) { [weak self] changeCount in
            self?.pasteEngine.lastSelfWriteChangeCount == changeCount
        }
        watcher.start()

        eventTap = EventTap(
            onKeyDown: { [weak self] keyCode, flags in
                self?.handleKeyDown(keyCode: keyCode, flags: flags) ?? false
            },
            onFlagsChanged: { [weak self] flags in
                self?.handleFlagsChanged(flags)
            }
        )

        setUpStatusItem()
        startTapOrPromptForPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap?.stop()
        watcher?.stop()
    }

    // MARK: - Permission

    private func startTapOrPromptForPermission() {
        if eventTap.start() {
            refreshStatusItem()
            return
        }
        EventTap.requestAccessibilityPermission()

        // Schedule the retry *before* showing the alert. `runModal()` blocks
        // the run loop, so a timer scheduled after it would not tick until the
        // user dismissed the alert -- and they grant the permission while it
        // is still on screen.
        startPermissionPolling()

        // Present on the next turn of the run loop for the same reason.
        DispatchQueue.main.async { [weak self] in
            self?.presentPermissionAlert()
        }
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard EventTap.hasAccessibilityPermission, self.eventTap.start() else { return }
            timer.invalidate()
            self.permissionTimer = nil
            self.refreshStatusItem()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "FlowKeys needs Accessibility access"
        alert.informativeText = """
        FlowKeys intercepts ⌘V so it can offer your clipboard history. \
        macOS requires Accessibility permission for that.

        Open System Settings → Privacy & Security → Accessibility and \
        enable FlowKeys. It starts working the moment you do — no restart.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Key handling

    /// Returns true to swallow the keystroke.
    private func handleKeyDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        if keyCode == KeyCode.escape, session.isActive {
            apply(session.cancel())
            return true
        }

        if keyCode == KeyCode.v, flags.contains(.maskCommand) {
            let backwards = flags.contains(.maskShift)
            visibleItems = store.items
            let effects = session.pasteKeyPressed(itemCount: visibleItems.count, backwards: backwards)
            if effects.contains(.passThrough) { return false }
            if session.phase == .armed { startRevealTimer() } else { cancelRevealTimer() }
            apply(effects)
            return true
        }

        // Everything below only applies once the overlay is actually up.
        guard session.phase == .cycling else {
            // Armed but not yet cycling: leave other keystrokes alone.
            if session.isActive { apply(session.cancel()) }
            return false
        }

        // Number keys jump straight to an entry.
        if let slot = numberSlot(for: keyCode), slot < visibleItems.count {
            apply(session.select(index: slot))
            return true
        }

        if keyCode == KeyCode.delete {
            let query = String(session.query.dropLast())
            visibleItems = filtered(by: query)
            apply(session.deleteQueryCharacter(matchCount: visibleItems.count))
            return true
        }

        // Type to filter. The user is holding ⌘, so these arrive as ⌘-letter
        // combinations; swallowing them is safe because we only get here while
        // the overlay is on screen.
        if let character = Self.character(for: keyCode), character.isLetter || character.isNumber
            || character == " " || character == "." || character == "-" || character == "/" {
            visibleItems = filtered(by: session.query + String(character))
            apply(session.appendToQuery(character, matchCount: visibleItems.count))
            return true
        }

        apply(session.cancel())
        return true
    }

    /// Case-insensitive substring match across the whole history.
    private func filtered(by query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return store.items }
        return store.items.filter { $0.text.range(of: query, options: .caseInsensitive) != nil }
    }

    private func numberSlot(for keyCode: Int64) -> Int? {
        // 1...9 select the first nine visible rows.
        guard let index = KeyCode.digitRow.firstIndex(of: keyCode) else { return nil }
        return index
    }

    private static func character(for keyCode: Int64) -> Character? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source,
                                  virtualKey: UInt16(keyCode), keyDown: true)
        else { return nil }
        // Read the key without modifiers so ⌘V-style combinations still
        // resolve to the plain letter.
        event.flags = []
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0, let scalar = String(utf16CodeUnits: chars, count: length).first else { return nil }
        return scalar
    }

    private func handleFlagsChanged(_ flags: CGEventFlags) {
        let held = flags.contains(.maskCommand)
        defer { commandHeld = held }
        guard commandHeld, !held, session.isActive else { return }
        cancelRevealTimer()
        apply(session.modifierReleased())
    }

    // MARK: - Effects

    private func apply(_ effects: [CycleSession.Effect]) {
        for effect in effects {
            switch effect {
            case .consume, .passThrough:
                break
            case .showOverlay(let index):
                overlay.show(
                    items: visibleItems,
                    selection: index,
                    query: session.query,
                    near: CaretLocator.overlayAnchor()
                )
            case .hideOverlay:
                overlay.hide()
            case .paste(let index):
                overlay.hide()
                // `index` addresses the filtered list, so map back by identity.
                guard visibleItems.indices.contains(index) else { break }
                let item = visibleItems[index]
                pasteEngine.paste(item) { [weak self] in
                    guard let self else { return }
                    // The pasted item becomes the most recent, so a plain ⌘V
                    // next time repeats what you just pasted.
                    if let storeIndex = self.store.items.firstIndex(where: { $0.id == item.id }) {
                        self.store.promote(index: storeIndex)
                    }
                    self.refreshStatusItem()
                }
            }
        }
    }

    private func startRevealTimer() {
        cancelRevealTimer()
        revealTimer = Timer.scheduledTimer(
            withTimeInterval: preferences.revealDelay, repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.apply(self.session.revealTimerFired())
        }
    }

    private func cancelRevealTimer() {
        revealTimer?.invalidate()
        revealTimer = nil
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "list.clipboard", accessibilityDescription: "FlowKeys"
        )
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshStatusItem()
    }

    /// Rebuild on every open. Permission can be granted while the app is
    /// running, and history changes constantly; a menu built once at launch
    /// would keep claiming the permission is missing after it was granted.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if !eventTap.isRunning, EventTap.hasAccessibilityPermission {
            _ = eventTap.start()
        }
        populate(menu)
    }

    private func refreshStatusItem() {
        statusItem?.button?.image = NSImage(
            systemSymbolName: eventTap.isRunning ? "list.clipboard.fill" : "list.clipboard",
            accessibilityDescription: "FlowKeys"
        )
        if let menu = statusItem?.menu { populate(menu) }
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !EventTap.hasAccessibilityPermission || !eventTap.isRunning {
            let warning = NSMenuItem(
                title: "⚠︎ Needs Accessibility access", action: #selector(openAccessibility), keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
            let hint = NSMenuItem(
                title: "    Already enabled? Quit and reopen FlowKeys.",
                action: nil, keyEquivalent: ""
            )
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(.separator())
        }

        // Another build running alongside this one will fight over ⌘V.
        let others = InstanceCheck.otherRunningBuilds()
        if !others.isEmpty {
            let warning = NSMenuItem(
                title: "⚠︎ Another FlowKeys is running", action: nil, keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.addItem(warning)
            for other in others {
                let detail = NSMenuItem(title: "    \(other.path)", action: nil, keyEquivalent: "")
                detail.isEnabled = false
                menu.addItem(detail)
            }
            let quitOthers = NSMenuItem(
                title: "Quit the other FlowKeys", action: #selector(quitOtherBuilds), keyEquivalent: ""
            )
            quitOthers.target = self
            menu.addItem(quitOthers)
            menu.addItem(.separator())
        }

        let header = NSMenuItem(title: "History (\(store.count))", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for (index, item) in store.items.prefix(10).enumerated() {
            let entry = NSMenuItem(
                title: "\(index + 1).  \(item.preview(maxLength: 48))",
                action: #selector(pasteFromMenu(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.tag = index
            menu.addItem(entry)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let login = NSMenuItem(
            title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: ""
        )
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(
            NSMenuItem(title: "Quit FlowKeys", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        menu.addItem(.separator())
        let footer = NSMenuItem(
            title: "v\(InstanceCheck.versionString) · \(InstanceCheck.locationDescription)",
            action: nil, keyEquivalent: ""
        )
        footer.isEnabled = false
        menu.addItem(footer)
    }

    @objc private func pasteFromMenu(_ sender: NSMenuItem) {
        guard let item = store.item(at: sender.tag) else { return }
        pasteEngine.paste(item) { [weak self] in
            self?.store.promote(index: sender.tag)
            self?.refreshStatusItem()
        }
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(preferences: preferences) { [weak self] updated in
            self?.applyPreferences(updated)
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "FlowKeys Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyPreferences(_ updated: Preferences) {
        preferences = updated
        store.forgetAfter = updated.forgetAfter
        store.purgeExpired()
        pasteEngine = PasteEngine(restoreClipboard: updated.restoreClipboardAfterPaste)
        refreshStatusItem()
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        refreshStatusItem()
    }

    @objc private func quitOtherBuilds() {
        let myPath = Bundle.main.bundlePath
        for app in NSWorkspace.shared.runningApplications {
            guard let url = app.bundleURL, url.path != myPath,
                  url.lastPathComponent.localizedCaseInsensitiveContains("FlowKeys")
            else { continue }
            app.terminate()
        }
        refreshStatusItem()
    }

    @objc private func clearHistory() {
        store.clear()
        refreshStatusItem()
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
