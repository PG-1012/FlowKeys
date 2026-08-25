import Foundation

/// In-memory clipboard history with optional disk persistence.
///
/// Ordering is most-recent-first, so index 0 is always what a plain ⌘V
/// would have pasted.
public final class ClipboardStore: @unchecked Sendable {

    public private(set) var items: [ClipboardItem] = []
    public let capacity: Int
    /// Drop unpinned entries older than this, if set. Limits how much of your
    /// copy history is sitting on disk at any one time.
    public var forgetAfter: TimeInterval?
    private let lock = NSLock()
    private let persistenceURL: URL?

    public init(
        capacity: Int = 50,
        persistenceURL: URL? = nil,
        forgetAfter: TimeInterval? = nil
    ) {
        self.capacity = max(1, capacity)
        self.persistenceURL = persistenceURL
        self.forgetAfter = forgetAfter
        if let url = persistenceURL { load(from: url) }
        purgeExpired()
    }

    /// Remove unpinned entries past their expiry. Safe to call often.
    public func purgeExpired(now: Date = Date()) {
        guard let forgetAfter else { return }
        lock.lock()
        let before = items.count
        items.removeAll { !$0.isPinned && now.timeIntervalSince($0.capturedAt) > forgetAfter }
        let changed = items.count != before
        lock.unlock()
        if changed { persist() }
    }

    public var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return items.isEmpty
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return items.count
    }

    public func item(at index: Int) -> ClipboardItem? {
        lock.lock(); defer { lock.unlock() }
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    /// Record a newly copied string.
    ///
    /// Re-copying something already in history moves it to the front rather
    /// than creating a duplicate — otherwise cycling fills up with repeats of
    /// whatever you copy most.
    @discardableResult
    public func record(_ text: String, sourceApp: String? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        lock.lock()
        if let existing = items.firstIndex(where: { $0.text == text }) {
            let item = items.remove(at: existing)
            items.insert(item, at: 0)
            lock.unlock()
            persist()
            return false
        }

        items.insert(ClipboardItem(text: text, sourceApp: sourceApp), at: 0)
        evictIfNeeded()
        lock.unlock()
        persist()
        return true
    }

    /// Move an item to the front without creating a new entry. Used after a
    /// paste so the thing you just pasted is what a plain ⌘V pastes next.
    public func promote(index: Int) {
        lock.lock()
        guard items.indices.contains(index) else { lock.unlock(); return }
        let item = items.remove(at: index)
        items.insert(item, at: 0)
        lock.unlock()
        persist()
    }

    public func togglePin(id: UUID) {
        lock.lock()
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].isPinned.toggle()
        }
        lock.unlock()
        persist()
    }

    public func remove(id: UUID) {
        lock.lock()
        items.removeAll { $0.id == id }
        lock.unlock()
        persist()
    }

    /// Clear history. Pinned items survive unless `includingPinned` is set.
    public func clear(includingPinned: Bool = false) {
        lock.lock()
        items = includingPinned ? [] : items.filter(\.isPinned)
        lock.unlock()
        persist()
    }

    /// Evict from the back, skipping pinned entries.
    private func evictIfNeeded() {
        guard items.count > capacity else { return }
        while items.count > capacity,
              let victim = items.lastIndex(where: { !$0.isPinned }) {
            items.remove(at: victim)
        }
        // Everything left is pinned and we are still over capacity: stop.
    }

    // MARK: - Persistence

    /// Write history to disk, owner-readable only.
    ///
    /// This file accumulates everything the user copies, which over time
    /// means passwords, tokens and private messages. The default file mode
    /// (0644) would leave all of that readable by every process and every
    /// other account on the machine, so both the directory and the file are
    /// forced to 0700/0600, and the file is kept out of backups.
    private func persist() {
        guard let url = persistenceURL else { return }
        lock.lock()
        let snapshot = items
        lock.unlock()

        let directory = url.deletingLastPathComponent()
        do {
            let fm = FileManager.default
            try fm.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

            var excluded = URLResourceValues()
            excluded.isExcludedFromBackup = true
            var mutable = url
            try? mutable.setResourceValues(excluded)
        } catch {
            // History is a convenience, not a system of record. Losing a
            // write should never take the app down.
        }
    }

    private func load(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else { return }
        items = Array(decoded.prefix(capacity))
    }
}
