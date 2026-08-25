import Foundation

/// In-memory clipboard history with optional disk persistence.
///
/// Ordering is most-recent-first, so index 0 is always what a plain ⌘V
/// would have pasted.
public final class ClipboardStore: @unchecked Sendable {

    public private(set) var items: [ClipboardItem] = []
    public let capacity: Int
    private let lock = NSLock()
    private let persistenceURL: URL?

    public init(capacity: Int = 50, persistenceURL: URL? = nil) {
        self.capacity = max(1, capacity)
        self.persistenceURL = persistenceURL
        if let url = persistenceURL { load(from: url) }
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

    private func persist() {
        guard let url = persistenceURL else { return }
        lock.lock()
        let snapshot = items
        lock.unlock()
        do {
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
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
