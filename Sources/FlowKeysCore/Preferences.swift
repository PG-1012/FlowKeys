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

    /// Bounds the settings UI enforces, and that `load` clamps to, so a
    /// hand-edited defaults plist cannot put the app in a silly state.
    public static let capacityRange = 5...200
    public static let revealDelayRange = 0.1...1.0

    // MARK: - Persistence

    private enum Key {
        static let capacity = "historyCapacity"
        static let revealDelay = "revealDelay"
        static let restore = "restoreClipboardAfterPaste"
        static let persist = "persistHistory"
        static let forgetAfterDays = "forgetAfterDays"
    }

    /// 0 means "never forget".
    public var forgetAfterDays: Int = 0

    public var forgetAfter: TimeInterval? {
        forgetAfterDays > 0 ? TimeInterval(forgetAfterDays) * 86_400 : nil
    }

    public static func load(from defaults: UserDefaults = .standard) -> Preferences {
        var prefs = Preferences.default
        if defaults.object(forKey: Key.capacity) != nil {
            prefs.historyCapacity = min(max(defaults.integer(forKey: Key.capacity),
                                            capacityRange.lowerBound), capacityRange.upperBound)
        }
        if defaults.object(forKey: Key.revealDelay) != nil {
            prefs.revealDelay = min(max(defaults.double(forKey: Key.revealDelay),
                                        revealDelayRange.lowerBound), revealDelayRange.upperBound)
        }
        if defaults.object(forKey: Key.restore) != nil {
            prefs.restoreClipboardAfterPaste = defaults.bool(forKey: Key.restore)
        }
        if defaults.object(forKey: Key.persist) != nil {
            prefs.persistHistory = defaults.bool(forKey: Key.persist)
        }
        prefs.forgetAfterDays = max(0, defaults.integer(forKey: Key.forgetAfterDays))
        return prefs
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(historyCapacity, forKey: Key.capacity)
        defaults.set(revealDelay, forKey: Key.revealDelay)
        defaults.set(restoreClipboardAfterPaste, forKey: Key.restore)
        defaults.set(persistHistory, forKey: Key.persist)
        defaults.set(forgetAfterDays, forKey: Key.forgetAfterDays)
    }

    public static var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FlowKeys/history.json")
    }
}
