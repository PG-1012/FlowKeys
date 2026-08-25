import Carbon.HIToolbox
import Cocoa
import FlowKeysCore

/// Places text on the pasteboard and synthesizes ⌘V into the frontmost app.
final class PasteEngine {

    private let restoreClipboard: Bool

    init(restoreClipboard: Bool) {
        self.restoreClipboard = restoreClipboard
    }

    /// Change count after our own write, so the clipboard watcher can tell
    /// our writes apart from a real user copy.
    private(set) var lastSelfWriteChangeCount: Int = -1

    func paste(_ item: ClipboardItem, completion: (() -> Void)? = nil) {
        let pasteboard = NSPasteboard.general

        // Snapshot what the user had, so we can hand it back afterwards.
        let previous = restoreClipboard ? pasteboard.string(forType: .string) : nil

        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastSelfWriteChangeCount = pasteboard.changeCount

        synthesizeCommandV()

        guard let previous, restoreClipboard else {
            completion?()
            return
        }

        // Give the target app time to read the pasteboard before restoring.
        // Too eager and the paste lands empty; this is the usual trade-off
        // for clipboard managers that restore.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
            self.lastSelfWriteChangeCount = pasteboard.changeCount
            completion?()
        }
    }

    /// Post a ⌘V key pair tagged so our own event tap ignores it.
    private func synthesizeCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: EventTap.syntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: EventTap.syntheticMarker)

        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
