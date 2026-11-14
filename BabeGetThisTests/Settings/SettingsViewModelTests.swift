import XCTest
@testable import BabeGetThis

/// Port of the Privacy and About parts of Android SettingsViewModel / SettingsScreen (SET-01, SET-02, STR-11).
@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "settings-vm-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeViewModel(
        versionName: String = "1.2.3",
        build: String = "45",
        appStoreID: String = "123456789"
    ) -> SettingsViewModel {
        SettingsViewModel(
            consent: UserDefaultsTelemetryConsentStore(defaults: defaults),
            infoDictionary: [
                "CFBundleShortVersionString": versionName,
                "CFBundleVersion": build,
                "BGTAppStoreID": appStoreID,
            ]
        )
    }

    func testSectionsArePrivacyThenAbout() {
        XCTAssertEqual(makeViewModel().sections, [.privacy, .about])
        XCTAssertEqual(SettingsSection.privacy.title, "Privacy")
        XCTAssertEqual(SettingsSection.about.title, "About")
    }

    func testVersionFooterFormat() {
        XCTAssertEqual(makeViewModel().versionFooter, "Version 1.2.3 (45)")
    }

    func testVersionFooterReadsBundleKeys() {
        // The name and the build come from their own keys, not each other's.
        let viewModel = SettingsViewModel(
            consent: UserDefaultsTelemetryConsentStore(defaults: defaults),
            infoDictionary: ["CFBundleShortVersionString": "2.0", "CFBundleVersion": "7", "CFBundleName": "x"]
        )
        XCTAssertEqual(viewModel.versionFooter, "Version 2.0 (7)")
    }

    func testVersionFooterDefaultsToTheAppsInfoPlist() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let name = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        let build = try XCTUnwrap(info["CFBundleVersion"] as? String)

        let viewModel = SettingsViewModel(consent: UserDefaultsTelemetryConsentStore(defaults: defaults))

        XCTAssertEqual(viewModel.versionFooter, "Version \(name) (\(build))")
    }

    func testBothConsentTogglesAreOnByDefault() {
        let viewModel = makeViewModel()
        XCTAssertTrue(viewModel.analyticsEnabled)
        XCTAssertTrue(viewModel.crashReportingEnabled)
    }

    func testAnalyticsToggleIsPersisted() {
        makeViewModel().setAnalyticsEnabled(false)
        XCTAssertFalse(defaults.bool(forKey: "analytics_enabled"))
        XCTAssertFalse(makeViewModel().analyticsEnabled)
        XCTAssertTrue(makeViewModel().crashReportingEnabled)
    }

    func testCrashReportingToggleIsPersisted() {
        let viewModel = makeViewModel()
        viewModel.setCrashReportingEnabled(false)
        XCTAssertFalse(viewModel.crashReportingEnabled)
        XCTAssertFalse(defaults.bool(forKey: "crash_reporting_enabled"))
        XCTAssertFalse(makeViewModel().crashReportingEnabled)
        XCTAssertTrue(makeViewModel().analyticsEnabled)
    }

    func testTogglingBackOnPersists() {
        let viewModel = makeViewModel()
        viewModel.setAnalyticsEnabled(false)
        viewModel.setAnalyticsEnabled(true)
        XCTAssertTrue(makeViewModel().analyticsEnabled)
    }

    func testRateRowOpensAppStoreReviewPage() {
        let viewModel = makeViewModel(appStoreID: "123456789")
        XCTAssertTrue(viewModel.showsRateRow)
        XCTAssertEqual(
            viewModel.rateURL?.absoluteString,
            "https://apps.apple.com/app/id123456789?action=write-review"
        )
    }

    func testRateRowIsHiddenWhileAppStoreIDIsEmpty() {
        let viewModel = makeViewModel(appStoreID: "")
        XCTAssertFalse(viewModel.showsRateRow)
        XCTAssertNil(viewModel.rateURL)
    }

    func testRateRowIsHiddenForUnexpandedBuildSetting() {
        XCTAssertFalse(makeViewModel(appStoreID: "$(BGT_APP_STORE_ID)").showsRateRow)
    }

    func testPrivacyPolicyURL() {
        XCTAssertEqual(
            makeViewModel().privacyPolicyURL.absoluteString,
            "https://babegetthis.com/privacy-policy.html"
        )
    }

    func testRowTextsUseAndroidWording() {
        XCTAssertEqual(SettingsStrings.analyticsTitle, "Usage analytics")
        XCTAssertEqual(SettingsStrings.analyticsSubtitle, "Which features get used, never what is on your lists.")
        XCTAssertEqual(SettingsStrings.crashTitle, "Crash reports")
        XCTAssertEqual(SettingsStrings.crashSubtitle, "Sends diagnostics when the app fails, so it can be fixed.")
        XCTAssertEqual(SettingsStrings.rateTitle, "Rate the app")
        XCTAssertEqual(SettingsStrings.rateSubtitle, "Leave a review on the App Store")
        XCTAssertEqual(SettingsStrings.privacyPolicyTitle, "Privacy policy")
        XCTAssertEqual(SettingsStrings.privacyPolicySubtitle, "What is collected and how it is used")
    }
}
