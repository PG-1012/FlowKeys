import Foundation

/// The paste-cycling state machine.
///
/// This is deliberately pure: no AppKit, no timers, no event taps. Every
/// decision FlowKeys makes about a keystroke happens here, so the behaviour
/// can be unit-tested without a running app or Accessibility permission.
///
/// The model is ⌘-Tab, applied to paste:
///
///   * Tap ⌘V and release  → paste the most recent item. No UI, no delay.
///     Ordinary paste is completely unchanged, which is the point.
///   * Hold ⌘ and tap V again → step to the next item, overlay appears.
///   * Keep holding ⌘, keep tapping V → keep stepping. ⇧ steps backwards.
///   * Release ⌘ → paste whatever is selected.
///   * Escape → cancel, paste nothing.
///
/// Holding ⌘ without tapping V again also reveals the overlay once
/// `revealDelay` elapses, so the feature is discoverable by hesitating.
public struct CycleSession: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        /// Nothing in progress.
        case idle
        /// ⌘V pressed once and ⌘ is still held. Overlay not shown yet.
        case armed
        /// Overlay is visible and the user is stepping through history.
        case cycling
    }

    /// What the caller should do as a result of an event.
    public enum Effect: Equatable, Sendable {
        /// Consume the keystroke; do nothing else yet.
        case consume
        /// Show or update the overlay at the given index.
        case showOverlay(index: Int)
        /// Hide the overlay.
        case hideOverlay
        /// Paste this index, then hide the overlay.
        case paste(index: Int)
        /// Let the keystroke through untouched (e.g. empty history).
        case passThrough
    }

    public private(set) var phase: Phase = .idle
    public private(set) var index: Int = 0
    private var itemCount: Int = 0

    public init() {}

    public var isActive: Bool { phase != .idle }

    // MARK: - Events

    /// ⌘V (or ⌘⇧V) was pressed. Returns the effects to apply, in order.
    public mutating func pasteKeyPressed(itemCount: Int, backwards: Bool = false) -> [Effect] {
        guard itemCount > 0 else {
            reset()
            return [.passThrough]
        }
        self.itemCount = itemCount

        switch phase {
        case .idle:
            // First press: arm on the most recent item but show nothing.
            // A quick tap-and-release must look exactly like a normal paste.
            phase = .armed
            index = 0
            return [.consume]

        case .armed:
            // Second press while ⌘ is still down: the user wants the picker.
            phase = .cycling
            index = step(from: 0, backwards: backwards)
            return [.consume, .showOverlay(index: index)]

        case .cycling:
            index = step(from: index, backwards: backwards)
            return [.consume, .showOverlay(index: index)]
        }
    }

    /// The reveal timer fired while armed: show the overlay without moving.
    public mutating func revealTimerFired() -> [Effect] {
        guard phase == .armed else { return [] }
        phase = .cycling
        return [.showOverlay(index: index)]
    }

    /// ⌘ was released. Commit whatever is selected.
    public mutating func modifierReleased() -> [Effect] {
        switch phase {
        case .idle:
            return []
        case .armed, .cycling:
            let target = index
            reset()
            return [.paste(index: target)]
        }
    }

    /// Escape (or any abort) pressed: drop out without pasting.
    public mutating func cancel() -> [Effect] {
        guard phase != .idle else { return [] }
        reset()
        return [.hideOverlay]
    }

    /// Jump directly to an index, e.g. from a number key or a click.
    public mutating func select(index newIndex: Int) -> [Effect] {
        guard phase != .idle, itemCount > 0 else { return [] }
        index = ((newIndex % itemCount) + itemCount) % itemCount
        phase = .cycling
        return [.showOverlay(index: index)]
    }

    // MARK: - Helpers

    private func step(from current: Int, backwards: Bool) -> Int {
        guard itemCount > 0 else { return 0 }
        let delta = backwards ? -1 : 1
        return ((current + delta) % itemCount + itemCount) % itemCount
    }

    private mutating func reset() {
        phase = .idle
        index = 0
        itemCount = 0
    }
}
