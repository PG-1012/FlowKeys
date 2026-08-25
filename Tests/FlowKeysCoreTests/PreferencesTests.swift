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

/// Delivery-method preferences. These exist because Microsoft Word ignored
/// the synthetic ⌘V that works everywhere else, so both the method and the
/// clipboard-restore window had to become user-tunable.
final class PasteMethodPreferenceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "flowkeys-paste-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsToKeystroke() {
        XCTAssertEqual(Preferences.load(from: defaults).pasteMethod, .keystroke)
    }

    func testPasteMethodRoundTrips() {
        var prefs = Preferences.default
        prefs.pasteMethod = .typed
        prefs.save(to: defaults)
        XCTAssertEqual(Preferences.load(from: defaults).pasteMethod, .typed)
    }

    func testUnknownStoredMethodFallsBackToDefault() {
        defaults.set("carrier-pigeon", forKey: "pasteMethod")
        XCTAssertEqual(Preferences.load(from: defaults).pasteMethod, .keystroke)
    }

    func testRestoreDelayRoundTripsAndClamps() {
        var prefs = Preferences.default
        prefs.restoreDelay = 0.9
        prefs.save(to: defaults)
        XCTAssertEqual(Preferences.load(from: defaults).restoreDelay, 0.9, accuracy: 0.0001)

        defaults.set(99.0, forKey: "restoreDelay")
        XCTAssertEqual(Preferences.load(from: defaults).restoreDelay,
                       Preferences.restoreDelayRange.upperBound)
    }

    func testEveryMethodHasATitle() {
        for method in PasteMethod.allCases {
            XCTAssertFalse(method.title.isEmpty)
        }
    }
}

/// Per-app delivery rules.
///
/// Word ignores a synthetic ⌘V however faithfully the key sequence is
/// reproduced, and nothing observable from outside reveals whether an app
/// read the pasteboard — so per-app rules, not auto-detection, are the
/// mechanism. These tests pin how a rule resolves.
final class PerAppPasteRuleTests: XCTestCase {

    func testKnownOffendersDefaultToTyping() {
        let prefs = Preferences.default
        XCTAssertEqual(prefs.method(forApp: "com.microsoft.Word"), .typed)
        XCTAssertEqual(prefs.method(forApp: "com.microsoft.Excel"), .typed)
    }

    func testOtherAppsUseTheGlobalDefault() {
        let prefs = Preferences.default
        XCTAssertEqual(prefs.method(forApp: "com.apple.TextEdit"), .keystroke)
    }

    func testUnknownAppUsesTheGlobalDefault() {
        XCTAssertEqual(Preferences.default.method(forApp: nil), .keystroke)
    }

    func testGlobalTypedDefaultAppliesEverywhere() {
        var prefs = Preferences.default
        prefs.pasteMethod = .typed
        XCTAssertEqual(prefs.method(forApp: "com.apple.TextEdit"), .typed)
    }

    func testAppCanBeAddedAndRemoved() {
        var prefs = Preferences.default
        prefs.typedApps.insert("com.example.Stubborn")
        XCTAssertEqual(prefs.method(forApp: "com.example.Stubborn"), .typed)

        prefs.typedApps.remove("com.example.Stubborn")
        XCTAssertEqual(prefs.method(forApp: "com.example.Stubborn"), .keystroke)
    }

    func testTypedAppsRoundTrip() {
        let suite = "flowkeys-apps-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var prefs = Preferences.default
        prefs.typedApps = ["com.a.One", "com.b.Two"]
        prefs.save(to: defaults)
        XCTAssertEqual(Preferences.load(from: defaults).typedApps, ["com.a.One", "com.b.Two"])
    }

    /// Removing every app must stick, rather than silently reverting to the
    /// seeded defaults on next launch.
    func testEmptiedListStaysEmpty() {
        let suite = "flowkeys-empty-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var prefs = Preferences.default
        prefs.typedApps = []
        prefs.save(to: defaults)
        XCTAssertTrue(Preferences.load(from: defaults).typedApps.isEmpty)
    }
}
