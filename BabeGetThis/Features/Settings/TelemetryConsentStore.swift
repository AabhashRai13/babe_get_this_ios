import Foundation

/// The user's choice for usage analytics and crash reports (port of Android `TelemetryConsent`).
/// Both default to ON. F44 applies these values to the Firebase SDKs.
protocol TelemetryConsentStore: AnyObject {
    var analyticsEnabled: Bool { get set }
    var crashReportingEnabled: Bool { get set }
}

/// `UserDefaults(suiteName: "telemetry_consent")` with Android's keys.
final class UserDefaultsTelemetryConsentStore: TelemetryConsentStore, @unchecked Sendable {
    static let suiteName = "telemetry_consent"
    static let analyticsKey = "analytics_enabled"
    static let crashReportingKey = "crash_reporting_enabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: UserDefaultsTelemetryConsentStore.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    var analyticsEnabled: Bool {
        get { read(Self.analyticsKey) }
        set { defaults.set(newValue, forKey: Self.analyticsKey) }
    }

    var crashReportingEnabled: Bool {
        get { read(Self.crashReportingKey) }
        set { defaults.set(newValue, forKey: Self.crashReportingKey) }
    }

    private func read(_ key: String) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }
}
