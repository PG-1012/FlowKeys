import XCTest
@testable import FlowKeysCore

final class PreferencesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "flowkeys-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsAreUsedWhenNothingIsStored() {
        let prefs = Preferences.load(from: defaults)
        XCTAssertEqual(prefs, {
            var expected = Preferences.default
            expected.forgetAfterDays = 0
            return expected
        }())
    }

    func testRoundTrip() {
        var prefs = Preferences.default
        prefs.historyCapacity = 120
        prefs.revealDelay = 0.6
        prefs.restoreClipboardAfterPaste = false
        prefs.persistHistory = false
        prefs.forgetAfterDays = 7
        prefs.save(to: defaults)

        let loaded = Preferences.load(from: defaults)
        XCTAssertEqual(loaded.historyCapacity, 120)
        XCTAssertEqual(loaded.revealDelay, 0.6, accuracy: 0.0001)
        XCTAssertFalse(loaded.restoreClipboardAfterPaste)
        XCTAssertFalse(loaded.persistHistory)
        XCTAssertEqual(loaded.forgetAfterDays, 7)
    }

    /// A hand-edited defaults plist should not be able to put the app into a
    /// nonsense state, e.g. a zero-item history or a five-second delay.
    func testOutOfRangeValuesAreClamped() {
        defaults.set(9999, forKey: "historyCapacity")
        defaults.set(45.0, forKey: "revealDelay")
        let high = Preferences.load(from: defaults)
        XCTAssertEqual(high.historyCapacity, Preferences.capacityRange.upperBound)
        XCTAssertEqual(high.revealDelay, Preferences.revealDelayRange.upperBound)

        defaults.set(-5, forKey: "historyCapacity")
        defaults.set(0.001, forKey: "revealDelay")
        let low = Preferences.load(from: defaults)
        XCTAssertEqual(low.historyCapacity, Preferences.capacityRange.lowerBound)
        XCTAssertEqual(low.revealDelay, Preferences.revealDelayRange.lowerBound)
    }

    func testForgetAfterConvertsDaysToSeconds() {
        var prefs = Preferences.default
        prefs.forgetAfterDays = 3
        XCTAssertEqual(prefs.forgetAfter, 3 * 86_400)
    }

    func testZeroDaysMeansNeverForget() {
        var prefs = Preferences.default
        prefs.forgetAfterDays = 0
        XCTAssertNil(prefs.forgetAfter)
    }

    func testNegativeForgetDaysAreTreatedAsNever() {
        defaults.set(-3, forKey: "forgetAfterDays")
        XCTAssertNil(Preferences.load(from: defaults).forgetAfter)
    }
}
