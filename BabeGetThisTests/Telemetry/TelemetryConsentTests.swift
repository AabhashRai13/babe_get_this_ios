import XCTest
@testable import BabeGetThis

/// Port of Android's TelemetryConsentTest, on F42's real UserDefaults store (a per-test suite):
/// an opt-out that forgets itself on relaunch is not an opt-out.
final class TelemetryConsentTests: XCTestCase {
    private let analytics = RecordingAnalytics()
    private let crashReporter = RecordingCrashReporter()
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TelemetryConsentTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// A new instance on the same storage, as after a relaunch.
    private func consent() -> TelemetryConsent {
        TelemetryConsent(store: UserDefaultsTelemetryConsentStore(defaults: defaults),
                         analytics: analytics, crashReporter: crashReporter)
    }

    func testCollectionIsOnByDefault() {
        // Opt-out. If this flips to opt-in for GDPR, this test should fail and force the decision.
        let consent = consent()

        XCTAssertTrue(consent.analyticsEnabled)
        XCTAssertTrue(consent.crashReportingEnabled)
    }

    func testOptingOutAppliesAtTheVendorNotJustInOurOwnState() {
        consent().setAnalyticsEnabled(false)

        XCTAssertEqual([false], analytics.collection)
    }

    func testTheChoiceSurvivesARelaunch() {
        consent().setAnalyticsEnabled(false)

        XCTAssertFalse(consent().analyticsEnabled)
    }

    func testOptingBackInSurvivesToo() {
        consent().setAnalyticsEnabled(false)
        consent().setAnalyticsEnabled(true)

        XCTAssertTrue(consent().analyticsEnabled)
    }

    func testTheTwoSwitchesAreIndependent() {
        let consent = consent()

        consent.setAnalyticsEnabled(false)

        XCTAssertFalse(consent.analyticsEnabled)
        XCTAssertTrue(consent.crashReportingEnabled)
    }

    func testCrashReportingOptsOutIndependently() {
        let consent = consent()

        consent.setCrashReportingEnabled(false)

        XCTAssertEqual([false], crashReporter.collection)
        XCTAssertTrue(consent.analyticsEnabled)
    }

    func testStartupReassertsTheStoredChoiceAtTheVendor() {
        consent().setAnalyticsEnabled(false)

        consent().applyPersisted()

        XCTAssertEqual(false, analytics.collection.last)
        XCTAssertEqual(true, crashReporter.collection.last)
    }
}
