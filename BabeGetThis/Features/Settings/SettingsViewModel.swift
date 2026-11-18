import Foundation
import Observation

/// Android's `settings_*` strings (SET-01, SET-02), with "App Store" where Android says Google Play.
enum SettingsStrings {
    static var title: String { String(localized: .settingsTitle) }
    static var privacySection: String { String(localized: .settingsPrivacySection) }
    static var aboutSection: String { String(localized: .settingsAboutSection) }
    static var analyticsTitle: String { String(localized: .settingsAnalyticsTitle) }
    static var analyticsSubtitle: String { String(localized: .settingsAnalyticsSubtitle) }
    static var crashTitle: String { String(localized: .settingsCrashTitle) }
    static var crashSubtitle: String { String(localized: .settingsCrashSubtitle) }
    static var rateTitle: String { String(localized: .settingsRateTitle) }
    static var rateSubtitle: String { String(localized: .settingsRateSubtitle) }
    static var privacyPolicyTitle: String { String(localized: .settingsPrivacyPolicyTitle) }
    static var privacyPolicySubtitle: String { String(localized: .settingsPrivacyPolicySubtitle) }
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

    /// `consent` is the container's `TelemetryConsent` in the app (it applies each change at the
    /// vendor); there is deliberately no default, so a screen can't fall back to a store that only
    /// writes UserDefaults. `infoDictionary` is the app's Info.plist, injectable for tests.
    init(consent: TelemetryConsentStore, infoDictionary info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        func string(_ key: String) -> String { info[key] as? String ?? "" }
        self.consent = consent
        analyticsEnabled = consent.analyticsEnabled
        crashReportingEnabled = consent.crashReportingEnabled
        versionFooter = Self.versionFooter(name: string("CFBundleShortVersionString"), build: string("CFBundleVersion"))
        rateURL = Self.rateURL(appStoreID: string("BGTAppStoreID"))
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
        String(localized: .settingsVersion(name, build))
    }

    nonisolated static func rateURL(appStoreID: String) -> URL? {
        let id = appStoreID.trimmingCharacters(in: .whitespaces)
        // An unexpanded "$(BGT_APP_STORE_ID)" counts as empty.
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }
}
