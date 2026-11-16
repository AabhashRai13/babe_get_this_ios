import SwiftUI
import XCTest
@testable import BabeGetThis

/// Port of the remaining Android `SettingsTest.kt` cases (SET-03): the five telemetry-consent cases
/// from `SettingsViewModelTest` and the privacy-policy row from `SettingsScreenTest`.
///
/// Not ported: the Got This, PIN/list lock and reminders cases (those features are out of v1), and
/// the four `SettingsRowTest` cases, which live in `SettingsRowTests` (UI-05).
@MainActor
final class SettingsTests: XCTestCase {

    // -- Telemetry consent --

    func testTheSwitchesStartFromTheStoredChoiceNotFromADefault() {
        let consent = RecordingConsentStore(analyticsEnabled: false, crashReportingEnabled: true)

        let viewModel = SettingsViewModel(consent: consent, infoDictionary: [:])

        XCTAssertFalse(viewModel.analyticsEnabled)
        XCTAssertTrue(viewModel.crashReportingEnabled)
    }

    func testOptingOutOfAnalyticsReachesTheConsentStore() {
        let consent = RecordingConsentStore()
        let viewModel = SettingsViewModel(consent: consent, infoDictionary: [:])

        viewModel.setAnalyticsEnabled(false)

        XCTAssertEqual(consent.analyticsWrites, [false])
        XCTAssertFalse(viewModel.analyticsEnabled)
    }

    func testOptingOutOfCrashReportingReachesTheConsentStore() {
        let consent = RecordingConsentStore()
        let viewModel = SettingsViewModel(consent: consent, infoDictionary: [:])

        viewModel.setCrashReportingEnabled(false)

        XCTAssertEqual(consent.crashReportingWrites, [false])
        XCTAssertFalse(viewModel.crashReportingEnabled)
    }

    func testTheTwoSwitchesAreIndependent() {
        // Crash reporting stands on different footing to product analytics, so dropping one must
        // never drop the other.
        let consent = RecordingConsentStore()
        let viewModel = SettingsViewModel(consent: consent, infoDictionary: [:])

        viewModel.setAnalyticsEnabled(false)

        XCTAssertEqual(consent.crashReportingWrites, [])
        XCTAssertTrue(viewModel.crashReportingEnabled)
    }

    func testOptingBackInReachesTheConsentStoreToo() {
        let consent = RecordingConsentStore()
        let viewModel = SettingsViewModel(consent: consent, infoDictionary: [:])

        viewModel.setAnalyticsEnabled(false)
        viewModel.setAnalyticsEnabled(true)

        XCTAssertEqual(consent.analyticsWrites, [false, true])
        XCTAssertTrue(viewModel.analyticsEnabled)
    }

    // -- Screen --

    // Android: Play's User Data policy wants the privacy policy reachable inside the app, not only
    // from the store listing. App Review asks the same (guideline 5.1.1).
    func testThePrivacyPolicyRowOpensThePublishedPolicy() throws {
        var opened: [URL] = []
        let hosted = HostedView(
            SettingsView(consent: RecordingConsentStore())
                .environment(\.openURL, OpenURLAction { url in
                    opened.append(url)
                    return .handled
                })
        )

        let row = try XCTUnwrap(hosted.element(labelled: "Privacy policy"), "labels: \(hosted.labels)")
        XCTAssertTrue(row.accessibilityActivate())

        XCTAssertEqual(opened.map(\.absoluteString), ["https://babegetthis.com/privacy-policy.html"])
    }
}

/// A consent store that remembers every write, standing in for Android's mocked `TelemetryConsent`.
/// The getters return the last value set, starting from the values given (both on, like production).
private final class RecordingConsentStore: TelemetryConsentStore {
    private(set) var analyticsWrites: [Bool] = []
    private(set) var crashReportingWrites: [Bool] = []
    private var analytics: Bool
    private var crashReporting: Bool

    init(analyticsEnabled: Bool = true, crashReportingEnabled: Bool = true) {
        analytics = analyticsEnabled
        crashReporting = crashReportingEnabled
    }

    var analyticsEnabled: Bool {
        get { analytics }
        set { analytics = newValue; analyticsWrites.append(newValue) }
    }

    var crashReportingEnabled: Bool {
        get { crashReporting }
        set { crashReporting = newValue; crashReportingWrites.append(newValue) }
    }
}
