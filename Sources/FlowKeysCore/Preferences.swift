import Foundation

/// User-tunable behaviour. Kept in Core so tests can construct it freely.
public struct Preferences: Equatable, Sendable {
    /// How many entries to keep.
    public var historyCapacity: Int
    /// How long ⌘ must be held after ⌘V before the overlay appears on its own.
    /// Short enough to feel responsive, long enough that a normal paste never
    /// flashes any UI.
    public var revealDelay: TimeInterval
    /// Restore the user's previous clipboard contents after pasting.
    public var restoreClipboardAfterPaste: Bool
    /// Persist history across launches.
    public var persistHistory: Bool

    public init(
        historyCapacity: Int = 50,
        revealDelay: TimeInterval = 0.25,
        restoreClipboardAfterPaste: Bool = true,
        persistHistory: Bool = true
    ) {
        self.historyCapacity = historyCapacity
        self.revealDelay = revealDelay
        self.restoreClipboardAfterPaste = restoreClipboardAfterPaste
        self.persistHistory = persistHistory
    }

    public static let `default` = Preferences()

    public static var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FlowKeys/history.json")
    }
}
