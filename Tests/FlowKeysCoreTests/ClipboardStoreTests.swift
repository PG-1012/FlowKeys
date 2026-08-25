import XCTest
@testable import FlowKeysCore

final class ClipboardStoreTests: XCTestCase {

    func testRecordsNewestFirst() {
        let store = ClipboardStore()
        store.record("first")
        store.record("second")
        XCTAssertEqual(store.item(at: 0)?.text, "second")
        XCTAssertEqual(store.item(at: 1)?.text, "first")
    }

    func testIgnoresEmptyAndWhitespaceOnlyCopies() {
        let store = ClipboardStore()
        XCTAssertFalse(store.record(""))
        XCTAssertFalse(store.record("   \n\t "))
        XCTAssertEqual(store.count, 0)
    }

    /// Re-copying something should not fill history with duplicates; it moves
    /// the existing entry to the front instead.
    func testRecopyingMovesToFrontWithoutDuplicating() {
        let store = ClipboardStore()
        store.record("a")
        store.record("b")
        store.record("c")
        XCTAssertFalse(store.record("a"), "Existing text is not a new capture")
        XCTAssertEqual(store.count, 3)
        XCTAssertEqual(store.items.map(\.text), ["a", "c", "b"])
    }

    func testEvictsOldestWhenOverCapacity() {
        let store = ClipboardStore(capacity: 3)
        ["a", "b", "c", "d"].forEach { store.record($0) }
        XCTAssertEqual(store.count, 3)
        XCTAssertEqual(store.items.map(\.text), ["d", "c", "b"])
    }

    func testPinnedItemsSurviveEviction() {
        let store = ClipboardStore(capacity: 3)
        store.record("keep")
        guard let pinned = store.item(at: 0) else { return XCTFail("missing item") }
        store.togglePin(id: pinned.id)

        ["a", "b", "c", "d"].forEach { store.record($0) }
        XCTAssertEqual(store.count, 3)
        XCTAssertTrue(store.items.contains { $0.text == "keep" }, "Pinned item was evicted")
    }

    func testPromoteMovesItemToFront() {
        let store = ClipboardStore()
        ["a", "b", "c"].forEach { store.record($0) }   // c, b, a
        store.promote(index: 2)                         // a to front
        XCTAssertEqual(store.items.map(\.text), ["a", "c", "b"])
    }

    func testPromoteWithBadIndexIsIgnored() {
        let store = ClipboardStore()
        store.record("a")
        store.promote(index: 99)
        XCTAssertEqual(store.items.map(\.text), ["a"])
    }

    func testClearKeepsPinnedByDefault() {
        let store = ClipboardStore()
        store.record("plain")
        store.record("sticky")
        guard let sticky = store.item(at: 0) else { return XCTFail("missing item") }
        store.togglePin(id: sticky.id)

        store.clear()
        XCTAssertEqual(store.items.map(\.text), ["sticky"])

        store.clear(includingPinned: true)
        XCTAssertTrue(store.isEmpty)
    }

    func testOutOfRangeAccessReturnsNil() {
        let store = ClipboardStore()
        XCTAssertNil(store.item(at: 0))
        store.record("a")
        XCTAssertNil(store.item(at: 5))
        XCTAssertNil(store.item(at: -1))
    }

    func testPersistenceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowkeys-test-\(UUID().uuidString)/history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ClipboardStore(capacity: 10, persistenceURL: url)
        store.record("persisted one")
        store.record("persisted two")

        let reloaded = ClipboardStore(capacity: 10, persistenceURL: url)
        XCTAssertEqual(reloaded.items.map(\.text), ["persisted two", "persisted one"])
    }
}

final class ClipboardItemTests: XCTestCase {

    func testPreviewCollapsesWhitespaceToOneLine() {
        let item = ClipboardItem(text: "line one\n\nline   two\tthree")
        XCTAssertEqual(item.preview(), "line one line two three")
    }

    func testPreviewTruncatesWithEllipsis() {
        let item = ClipboardItem(text: String(repeating: "x", count: 200))
        let preview = item.preview(maxLength: 20)
        XCTAssertEqual(preview.count, 21, "20 characters plus the ellipsis")
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    func testPreviewLeavesShortTextAlone() {
        XCTAssertEqual(ClipboardItem(text: "short").preview(), "short")
    }

    func testSummaryReportsLineCountOnlyForMultilineText() {
        XCTAssertEqual(ClipboardItem(text: "abc").summary, "3 chars")
        XCTAssertEqual(ClipboardItem(text: "a\nb").summary, "3 chars · 2 lines")
    }
}

/// The history file accumulates everything the user copies. These tests
/// defend the two properties that keeps tolerable: it is not readable by
/// anyone else, and entries do not live forever.
final class ClipboardStorePrivacyTests: XCTestCase {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("flowkeys-priv-\(UUID().uuidString)/history.json")
    }

    func testHistoryFileIsOwnerReadableOnly() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ClipboardStore(capacity: 5, persistenceURL: url)
        store.record("something private")

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(mode, 0o600, "History must not be readable by other users")
    }

    func testHistoryDirectoryIsOwnerOnly() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ClipboardStore(capacity: 5, persistenceURL: url)
        store.record("something private")

        let attrs = try FileManager.default.attributesOfItem(
            atPath: url.deletingLastPathComponent().path
        )
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testExpiredEntriesArePurged() {
        let store = ClipboardStore(capacity: 10, forgetAfter: 3600)
        store.record("old")
        store.record("recent")

        // Two hours on, only entries newer than an hour should remain.
        store.purgeExpired(now: Date().addingTimeInterval(7200))
        XCTAssertTrue(store.isEmpty, "Everything is older than the window")
    }

    func testPinnedEntriesNeverExpire() {
        let store = ClipboardStore(capacity: 10, forgetAfter: 60)
        store.record("keep me")
        guard let item = store.item(at: 0) else { return XCTFail("missing item") }
        store.togglePin(id: item.id)

        store.purgeExpired(now: Date().addingTimeInterval(3600))
        XCTAssertEqual(store.items.map(\.text), ["keep me"])
    }

    func testNoExpiryWindowKeepsEverything() {
        let store = ClipboardStore(capacity: 10)
        store.record("a")
        store.purgeExpired(now: Date().addingTimeInterval(86_400 * 365))
        XCTAssertEqual(store.count, 1)
    }
}
