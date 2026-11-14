import Foundation
import Observation

/// Android's `settings_*` strings (SET-01, SET-02), with "App Store" where Android says Google Play.
enum SettingsStrings {
    static let title = "Settings"
    static let privacySection = "Privacy"
    static let aboutSection = "About"
    static let analyticsTitle = "Usage analytics"
    static let analyticsSubtitle = "Which features get used, never what is on your lists."
    static let crashTitle = "Crash reports"
    static let crashSubtitle = "Sends diagnostics when the app fails, so it can be fixed."
    static let rateTitle = "Rate the app"
    static let rateSubtitle = "Leave a review on the App Store"
    static let privacyPolicyTitle = "Privacy policy"
    static let privacyPolicySubtitle = "What is collected and how it is used"
}

/// Settings sections, in display order. Android's List lock and Reminders sections are out of v1.
enum SettingsSection: Equatable {
    case privacy
    case about

    var title: String {
        switch self {
        case .privacy: SettingsStrings.privacySection
        case .about: SettingsStrings.aboutSection
        }
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    /// Android `PRIVACY_POLICY_URL`.
    static let privacyPolicyURLString = "https://babegetthis.com/privacy-policy.html"

    let sections: [SettingsSection] = [.privacy, .about]
    let versionFooter: String
    let privacyPolicyURL = URL(string: SettingsViewModel.privacyPolicyURLString)!
    /// The App Store review page, or nil while the app has no listing (empty `BGTAppStoreID`).
    let rateURL: URL?

    private(set) var analyticsEnabled: Bool
    private(set) var crashReportingEnabled: Bool

    private let consent: TelemetryConsentStore

    var showsRateRow: Bool { rateURL != nil }

    init(
        consent: TelemetryConsentStore = UserDefaultsTelemetryConsentStore(),
        versionName: String = SettingsViewModel.bundleString("CFBundleShortVersionString"),
        build: String = SettingsViewModel.bundleString("CFBundleVersion"),
        appStoreID: String = SettingsViewModel.bundleString("BGTAppStoreID")
    ) {
        self.consent = consent
        analyticsEnabled = consent.analyticsEnabled
        crashReportingEnabled = consent.crashReportingEnabled
        versionFooter = Self.versionFooter(name: versionName, build: build)
        rateURL = Self.rateURL(appStoreID: appStoreID)
    }

    func setAnalyticsEnabled(_ enabled: Bool) {
        consent.analyticsEnabled = enabled
        analyticsEnabled = enabled
    }

    func setCrashReportingEnabled(_ enabled: Bool) {
        consent.crashReportingEnabled = enabled
        crashReportingEnabled = enabled
    }

    nonisolated static func versionFooter(name: String, build: String) -> String {
        "Version \(name) (\(build))"
    }

    nonisolated static func rateURL(appStoreID: String) -> URL? {
        let id = appStoreID.trimmingCharacters(in: .whitespaces)
        // An unexpanded "$(BGT_APP_STORE_ID)" counts as empty.
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }

    nonisolated static func bundleString(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
