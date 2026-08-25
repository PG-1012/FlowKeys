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
    private let onKeyDown: KeyHandler
    private let onFlagsChanged: FlagsHandler

    /// Marks events we synthesize ourselves so the tap ignores them and we do
    /// not recurse when posting the real paste.
    static let syntheticMarker: Int64 = 0x464C4F57  // 'FLOW'

    init(onKeyDown: @escaping KeyHandler, onFlagsChanged: @escaping FlagsHandler) {
        self.onKeyDown = onKeyDown
        self.onFlagsChanged = onFlagsChanged
    }

    var isRunning: Bool { tap != nil }

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

        // Never process our own synthesized paste.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            onFlagsChanged(event.flags)
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if onKeyDown(keyCode, event.flags) {
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
    static let one: Int64 = Int64(kVK_ANSI_1)
}
