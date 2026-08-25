import Cocoa
import FlowKeysCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var preferences = Preferences.default
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
            persistenceURL: preferences.persistHistory ? Preferences.storageURL : nil
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

        guard keyCode == KeyCode.v, flags.contains(.maskCommand) else {
            // Any other key while cycling aborts, so the keystroke is not lost.
            if session.isActive { apply(session.cancel()) }
            return false
        }

        let backwards = flags.contains(.maskShift)
        let effects = session.pasteKeyPressed(itemCount: store.count, backwards: backwards)

        if effects.contains(.passThrough) { return false }

        // While armed, start the timer that reveals the overlay if the user
        // simply keeps holding ⌘ without tapping V again.
        if session.phase == .armed { startRevealTimer() } else { cancelRevealTimer() }

        apply(effects)
        return true
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
                    items: store.items,
                    selection: index,
                    near: CaretLocator.overlayAnchor()
                )
            case .hideOverlay:
                overlay.hide()
            case .paste(let index):
                overlay.hide()
                guard let item = store.item(at: index) else { break }
                pasteEngine.paste(item) { [weak self] in
                    // The pasted item becomes the most recent, so a plain ⌘V
                    // next time repeats what you just pasted.
                    self?.store.promote(index: index)
                    self?.refreshStatusItem()
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
    }

    @objc private func pasteFromMenu(_ sender: NSMenuItem) {
        guard let item = store.item(at: sender.tag) else { return }
        pasteEngine.paste(item) { [weak self] in
            self?.store.promote(index: sender.tag)
            self?.refreshStatusItem()
        }
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
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
