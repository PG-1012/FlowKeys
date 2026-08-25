import ApplicationServices
import Carbon.HIToolbox
import Cocoa

/// Intercepts ⌘V system-wide.
///
/// Why `CGEvent.tapCreate` and not `NSEvent.addGlobalMonitorForEvents`:
/// a global monitor is **passive**. It can observe a keystroke but cannot stop
/// it, so the real paste fires in the frontmost app the instant ⌘V is pressed
/// and there is no way to substitute a different item. An event tap created
/// with `.defaultTap` can return `nil` to swallow the event, which is what
/// makes hold-to-cycle possible at all.
///
/// This requires Accessibility permission (System Settings → Privacy &
/// Security → Accessibility).
final class EventTap {

    /// Called for each intercepted key event. Return `true` to swallow it.
    typealias KeyHandler = (_ keyCode: Int64, _ flags: CGEventFlags) -> Bool
    /// Called when the modifier set changes.
    typealias FlagsHandler = (_ flags: CGEventFlags) -> Void

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Wall-clock deadline before which every event is passed straight
    /// through. See `suppressSelfGenerated(for:)`.
    private var suppressUntil: CFAbsoluteTime = 0
    private let onKeyDown: KeyHandler
    private let onFlagsChanged: FlagsHandler

    /// Marks events we synthesize ourselves so the tap ignores them and we do
    /// not recurse when posting the real paste.
    ///
    /// This alone is not sufficient. Events posted to `.cghidEventTap` travel
    /// the full input stack and the user-data field does not reliably survive
    /// the round trip, so a synthetic ⌘V can come back looking like a real one
    /// and get swallowed by our own tap — the paste then silently does
    /// nothing. `suppressSelfGenerated(for:)` is the reliable guard; this
    /// marker is a cheap first check.
    static let syntheticMarker: Int64 = 0x464C4F57  // 'FLOW'

    init(onKeyDown: @escaping KeyHandler, onFlagsChanged: @escaping FlagsHandler) {
        self.onKeyDown = onKeyDown
        self.onFlagsChanged = onFlagsChanged
    }

    var isRunning: Bool { tap != nil }

    /// Pass every event straight through for `interval` seconds.
    ///
    /// Called immediately before synthesizing a paste. Time-boxed rather than
    /// a plain boolean so a dropped or reordered event can never leave the tap
    /// permanently disabled.
    func suppressSelfGenerated(for interval: TimeInterval) {
        suppressUntil = CFAbsoluteTimeGetCurrent() + interval
    }

    /// Whether the process currently holds Accessibility permission.
    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    /// Ask the system to show the Accessibility prompt.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,           // .listenOnly cannot swallow events
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        return true
    }

    func stop() {
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that takes too long or hits an input
        // backlog. Re-enable rather than silently dying.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Never process our own synthesized paste, by either guard.
        if CFAbsoluteTimeGetCurrent() < suppressUntil {
            Log.tap.debug("passing through self-generated event")
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            Log.tap.debug("passing through marked event")
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            onFlagsChanged(event.flags)
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if onKeyDown(keyCode, event.flags) {
                Log.tap.debug("swallowed keyCode \(keyCode, privacy: .public)")
                return nil  // swallow
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

enum KeyCode {
    static let v: Int64 = Int64(kVK_ANSI_V)
    static let escape: Int64 = Int64(kVK_Escape)
    static let delete: Int64 = Int64(kVK_Delete)
    /// Virtual key codes for 1...9 in row order (they are not contiguous).
    static let digitRow: [Int64] = [
        Int64(kVK_ANSI_1), Int64(kVK_ANSI_2), Int64(kVK_ANSI_3),
        Int64(kVK_ANSI_4), Int64(kVK_ANSI_5), Int64(kVK_ANSI_6),
        Int64(kVK_ANSI_7), Int64(kVK_ANSI_8), Int64(kVK_ANSI_9),
    ]
}
