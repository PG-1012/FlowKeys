import XCTest
@testable import FlowKeysCore

/// The whole product is one interaction, so it gets tested properly.
///
/// The rule these tests defend: **an ordinary paste must stay ordinary.**
/// Tap ⌘V and release and you get item 0 with no overlay, exactly like the
/// system paste. Everything else is opt-in by keeping ⌘ held.
final class CycleSessionTests: XCTestCase {

    private var session = CycleSession()

    override func setUp() {
        super.setUp()
        session = CycleSession()
    }

    // MARK: - Ordinary paste

    func testSingleTapArmsWithoutShowingOverlay() {
        let effects = session.pasteKeyPressed(itemCount: 5)
        XCTAssertEqual(effects, [.consume])
        XCTAssertEqual(session.phase, .armed)
        XCTAssertEqual(session.index, 0)
    }

    func testTapAndReleasePastesMostRecent() {
        _ = session.pasteKeyPressed(itemCount: 5)
        let effects = session.modifierReleased()
        XCTAssertEqual(effects, [.paste(index: 0)])
        XCTAssertEqual(session.phase, .idle)
    }

    func testNoOverlayIsEverShownForAPlainPaste() {
        _ = session.pasteKeyPressed(itemCount: 5)
        let effects = session.modifierReleased()
        XCTAssertFalse(effects.contains { if case .showOverlay = $0 { return true }; return false })
    }

    // MARK: - Cycling

    func testSecondTapStartsCyclingAtIndexOne() {
        _ = session.pasteKeyPressed(itemCount: 5)
        let effects = session.pasteKeyPressed(itemCount: 5)
        XCTAssertEqual(effects, [.consume, .showOverlay(index: 1)])
        XCTAssertEqual(session.phase, .cycling)
    }

    func testFurtherTapsAdvanceOneAtATime() {
        _ = session.pasteKeyPressed(itemCount: 5)   // armed, 0
        _ = session.pasteKeyPressed(itemCount: 5)   // cycling, 1
        _ = session.pasteKeyPressed(itemCount: 5)   // 2
        _ = session.pasteKeyPressed(itemCount: 5)   // 3
        XCTAssertEqual(session.index, 3)
    }

    func testCyclingWrapsAround() {
        _ = session.pasteKeyPressed(itemCount: 3)   // armed, 0
        _ = session.pasteKeyPressed(itemCount: 3)   // 1
        _ = session.pasteKeyPressed(itemCount: 3)   // 2
        _ = session.pasteKeyPressed(itemCount: 3)   // wraps to 0
        XCTAssertEqual(session.index, 0)
    }

    func testShiftCyclesBackwards() {
        _ = session.pasteKeyPressed(itemCount: 5)                    // armed, 0
        _ = session.pasteKeyPressed(itemCount: 5, backwards: true)   // wraps to 4
        XCTAssertEqual(session.index, 4)
        _ = session.pasteKeyPressed(itemCount: 5, backwards: true)   // 3
        XCTAssertEqual(session.index, 3)
    }

    func testReleasingWhileCyclingPastesTheSelectedItem() {
        _ = session.pasteKeyPressed(itemCount: 5)
        _ = session.pasteKeyPressed(itemCount: 5)
        _ = session.pasteKeyPressed(itemCount: 5)
        XCTAssertEqual(session.modifierReleased(), [.paste(index: 2)])
    }

    // MARK: - Reveal by hesitating

    func testHoldingWithoutTappingRevealsOverlayInPlace() {
        _ = session.pasteKeyPressed(itemCount: 5)
        let effects = session.revealTimerFired()
        XCTAssertEqual(effects, [.showOverlay(index: 0)])
        XCTAssertEqual(session.index, 0, "Revealing must not move the selection")
        XCTAssertEqual(session.phase, .cycling)
    }

    func testRevealTimerDoesNothingWhenIdle() {
        XCTAssertTrue(session.revealTimerFired().isEmpty)
    }

    func testRevealThenReleasePastesMostRecent() {
        _ = session.pasteKeyPressed(itemCount: 5)
        _ = session.revealTimerFired()
        XCTAssertEqual(session.modifierReleased(), [.paste(index: 0)])
    }

    // MARK: - Cancelling

    func testEscapeHidesOverlayAndPastesNothing() {
        _ = session.pasteKeyPressed(itemCount: 5)
        _ = session.pasteKeyPressed(itemCount: 5)
        XCTAssertEqual(session.cancel(), [.hideOverlay])
        XCTAssertEqual(session.phase, .idle)
    }

    func testReleasingAfterCancelPastesNothing() {
        _ = session.pasteKeyPressed(itemCount: 5)
        _ = session.cancel()
        XCTAssertTrue(session.modifierReleased().isEmpty)
    }

    func testCancelWhenIdleIsANoOp() {
        XCTAssertTrue(session.cancel().isEmpty)
    }

    // MARK: - Edge cases

    func testEmptyHistoryPassesTheKeystrokeThrough() {
        let effects = session.pasteKeyPressed(itemCount: 0)
        XCTAssertEqual(effects, [.passThrough])
        XCTAssertEqual(session.phase, .idle, "Must not swallow ⌘V with nothing to offer")
    }

    func testSingleItemHistoryStaysOnThatItem() {
        _ = session.pasteKeyPressed(itemCount: 1)
        _ = session.pasteKeyPressed(itemCount: 1)
        _ = session.pasteKeyPressed(itemCount: 1)
        XCTAssertEqual(session.index, 0)
        XCTAssertEqual(session.modifierReleased(), [.paste(index: 0)])
    }

    func testDirectSelectionJumpsAndShowsOverlay() {
        _ = session.pasteKeyPressed(itemCount: 5)
        XCTAssertEqual(session.select(index: 3), [.showOverlay(index: 3)])
        XCTAssertEqual(session.modifierReleased(), [.paste(index: 3)])
    }

    func testSelectionWrapsNegativeAndOversizedIndices() {
        _ = session.pasteKeyPressed(itemCount: 5)
        _ = session.select(index: -1)
        XCTAssertEqual(session.index, 4)
        _ = session.select(index: 7)
        XCTAssertEqual(session.index, 2)
    }

    func testSessionIsReusableAfterCommitting() {
        _ = session.pasteKeyPressed(itemCount: 3)
        _ = session.pasteKeyPressed(itemCount: 3)
        _ = session.modifierReleased()

        _ = session.pasteKeyPressed(itemCount: 3)
        XCTAssertEqual(session.phase, .armed)
        XCTAssertEqual(session.index, 0, "A new session must start from the most recent item")
    }

    func testHistoryShrinkingBetweenTapsStaysInBounds() {
        _ = session.pasteKeyPressed(itemCount: 10)
        _ = session.pasteKeyPressed(itemCount: 10)
        _ = session.pasteKeyPressed(itemCount: 10)   // index 2
        // History was cleared down to 2 entries between keystrokes.
        _ = session.pasteKeyPressed(itemCount: 2)
        XCTAssertTrue((0..<2).contains(session.index), "index \(session.index) out of range")
    }
}
