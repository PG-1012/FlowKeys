import Cocoa
import FlowKeysCore
import SwiftUI

/// Borderless, non-activating panel that hosts `OverlayView`.
///
/// It must never take key focus: the user is mid-keystroke in another app,
/// and stealing focus would break the paste we are about to perform.
final class OverlayPanel {

    private var panel: NSPanel?
    private var hosting: NSHostingView<OverlayView>?

    private static let margin: CGFloat = 14

    func show(items: [ClipboardItem], selection: Int, near anchor: NSPoint) {
        let view = OverlayView(items: items, selection: selection)

        if let hosting {
            hosting.rootView = view
        } else {
            let hostingView = NSHostingView(rootView: view)
            let created = NSPanel(
                contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false          // the SwiftUI view draws its own
            created.level = .popUpMenu
            created.ignoresMouseEvents = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            created.hidesOnDeactivate = false
            created.contentView = hostingView

            panel = created
            hosting = hostingView
        }

        guard let panel, let hosting else { return }
        panel.setContentSize(hosting.fittingSize)
        panel.setFrameOrigin(position(for: panel.frame.size, anchor: anchor))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Place the panel just below the anchor, nudged back on screen if it
    /// would spill off an edge.
    private func position(for size: NSSize, anchor: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        var x = anchor.x
        var y = anchor.y - size.height - Self.margin

        if x + size.width > visible.maxX { x = visible.maxX - size.width - Self.margin }
        if x < visible.minX { x = visible.minX + Self.margin }
        // Not enough room below the caret: flip above it.
        if y < visible.minY { y = anchor.y + Self.margin }
        if y + size.height > visible.maxY { y = visible.maxY - size.height - Self.margin }

        return NSPoint(x: x, y: y)
    }
}
