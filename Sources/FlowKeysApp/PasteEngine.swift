import Carbon.HIToolbox
import Cocoa
import FlowKeysCore

/// Places text on the pasteboard and synthesizes ⌘V into the frontmost app.
final class PasteEngine {

    private let restoreClipboard: Bool
    private let restoreDelay: TimeInterval

    /// The user's physical ⌘ release and our synthetic press must not
    /// overlap, or an app tracking modifier state sees them interleaved.
    private static let settleDelay: TimeInterval = 0.03

    /// Resolved per paste, since it depends on which app is frontmost.
    var methodResolver: ((String?) -> PasteMethod)?
    private let method: PasteMethod
    /// Called just before any synthetic event is posted, so the event tap can
    /// ignore what we are about to generate.
    var willSynthesize: ((TimeInterval) -> Void)?

    init(
        restoreClipboard: Bool,
        restoreDelay: TimeInterval = 0.35,
        method: PasteMethod = .keystroke
    ) {
        self.restoreClipboard = restoreClipboard
        self.restoreDelay = restoreDelay
        self.method = method
    }

    /// Change count after our own write, so the clipboard watcher can tell
    /// our writes apart from a real user copy.
    private(set) var lastSelfWriteChangeCount: Int = -1

    /// - Parameter targetApp: bundle identifier of the app being pasted into.
    ///   Delivery is chosen per app, because some apps ignore a synthetic ⌘V
    ///   and nothing observable reveals that from outside.
    func paste(
        _ item: ClipboardItem,
        into targetApp: String? = nil,
        completion: (() -> Void)? = nil
    ) {
        let method = methodResolver?(targetApp) ?? self.method
        Log.paste.debug(
            "paste into \(targetApp ?? "unknown", privacy: .public) via \(String(describing: method), privacy: .public)"
        )
        // Typing bypasses the pasteboard entirely, so it neither disturbs the
        // user's clipboard nor depends on the target app's paste handling.
        if method == .typed {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) {
                self.typeText(item.text)
                completion?()
            }
            return
        }

        let pasteboard = NSPasteboard.general

        // Snapshot what the user had, so we can hand it back afterwards.
        let previous = restoreClipboard ? pasteboard.string(forType: .string) : nil

        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastSelfWriteChangeCount = pasteboard.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) {
            self.synthesizeCommandV()

            guard let previous, self.restoreClipboard else {
                completion?()
                return
            }

            // Give the target app time to read the pasteboard before we put
            // the old contents back. Restore too eagerly and a slow app --
            // Word is the usual offender -- reads after the swap and pastes
            // the wrong thing. Every clipboard manager makes this trade-off.
            DispatchQueue.main.asyncAfter(deadline: .now() + self.restoreDelay) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
                self.lastSelfWriteChangeCount = pasteboard.changeCount
                completion?()
            }
        }
    }

    /// Synthesize the text as keystrokes.
    ///
    /// `keyboardSetUnicodeString` lets a key event carry arbitrary text
    /// regardless of keyboard layout. Events are sent in small chunks because
    /// a single event carrying a very long string is unreliable.
    private func typeText(_ text: String) {
        willSynthesize?(max(0.3, Double(text.count) * 0.002))

        let source = CGEventSource(stateID: .combinedSessionState)
        let units = Array(text.utf16)
        let chunkSize = 16
        var offset = 0

        while offset < units.count {
            var chunk = Array(units[offset..<min(offset + chunkSize, units.count)])
            offset += chunkSize

            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }

            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            for event in [down, up] {
                event.setIntegerValueField(.eventSourceUserData, value: EventTap.syntheticMarker)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Post a complete, coherent ⌘V sequence.
    ///
    /// Posting only V-down/V-up with `.maskCommand` set is enough for apps
    /// that read `event.flags` directly, which is most of AppKit. It is not
    /// enough for apps that track modifier state from `flagsChanged` events —
    /// Microsoft Word and many Electron apps do. By the time we paste, the
    /// user has just *released* ⌘, so those apps believe ⌘ is up, see a V
    /// claiming otherwise, and either ignore it or type a literal "v".
    ///
    /// So we post the modifier key events too, giving every app a sequence
    /// that is internally consistent no matter how it tracks state.
    ///
    /// Events go to `.cghidEventTap`, which injects low enough in the stack
    /// that apps with their own event handling still see them.
    private func synthesizeCommandV() {
        // Blanket-ignore our own events for the duration of the sequence.
        willSynthesize?(0.3)
        Log.paste.debug("synthesizing Cmd-V")

        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let command = UInt16(kVK_Command)
        let v = UInt16(kVK_ANSI_V)

        guard
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: false)
        else { return }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandUp.flags = []

        // Mark every event so our own tap skips them instead of recursing.
        for event in [commandDown, vDown, vUp, commandUp] {
            event.setIntegerValueField(.eventSourceUserData, value: EventTap.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
        Log.paste.debug("posted Cmd-V sequence")
    }
}
