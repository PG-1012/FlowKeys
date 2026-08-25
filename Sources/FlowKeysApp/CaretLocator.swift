import ApplicationServices
import Cocoa

/// Finds where to put the overlay.
///
/// Preference order:
///   1. The text caret in the focused element, via the Accessibility API.
///      This is what makes the overlay appear *at* what you are typing.
///   2. The mouse pointer, when the focused app exposes no caret (many
///      Electron apps, some terminals).
enum CaretLocator {

    static func overlayAnchor() -> NSPoint {
        caretScreenPoint() ?? NSEvent.mouseLocation
    }

    private static func caretScreenPoint() -> NSPoint? {
        let system = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let element = focused else { return nil }

        // swiftlint:disable:next force_cast
        let axElement = element as! AXUIElement

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        ) == .success, let rangeValue else { return nil }

        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            axElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &bounds
        ) == .success, let bounds else { return nil }

        var rect = CGRect.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.width.isFinite, rect.height.isFinite,
              !(rect.origin.x == 0 && rect.origin.y == 0) else { return nil }

        // AX reports top-left origin; AppKit screen coordinates are
        // bottom-left, so flip against the primary screen height.
        guard let primary = NSScreen.screens.first else { return nil }
        let flippedY = primary.frame.height - rect.origin.y
        return NSPoint(x: rect.origin.x, y: flippedY)
    }
}
