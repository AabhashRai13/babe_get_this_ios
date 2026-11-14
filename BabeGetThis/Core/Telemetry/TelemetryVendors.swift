@preconcurrency import FirebaseCore
import Foundation

/// The Firebase app settings from Info.plist (filled per environment from Secrets.xcconfig).
/// Staging and Prod use separate Firebase projects; Dev sends nothing (TEL-01).
struct FirebaseSettings: Equatable, Sendable {
    static let googleAppIDKey = "BGTFirebaseGoogleAppID"
    static let gcmSenderIDKey = "BGTFirebaseGCMSenderID"
    static let apiKeyKey = "BGTFirebaseAPIKey"
    static let projectIDKey = "BGTFirebaseProjectID"

    let googleAppID: String
    let gcmSenderID: String
    let apiKey: String
    let projectID: String

    /// The settings to configure Firebase with, or nil when it must stay off: always in Dev,
    /// and whenever any of the four values is missing or blank.
    static func resolve(infoDictionary info: [String: Any], environment: AppConfig.Environment) -> FirebaseSettings? {
        guard environment != .dev else { return nil }
        func value(_ key: String) -> String? {
            let raw = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? nil : raw
        }
        guard let googleAppID = value(googleAppIDKey), let gcmSenderID = value(gcmSenderIDKey),
              let apiKey = value(apiKeyKey), let projectID = value(projectIDKey) else { return nil }
        return FirebaseSettings(googleAppID: googleAppID, gcmSenderID: gcmSenderID, apiKey: apiKey, projectID: projectID)
    }
}

/// The analytics and crash-reporting implementations the app runs with: Firebase when it is
/// configured, no-ops otherwise. The whole vendor commitment is in this type.
struct TelemetryVendors: Sendable {
    let analytics: any AnalyticsRepository
    let crashReporter: any CrashReporter

    /// Sends nothing and never touches Firebase.
    static let noOp = TelemetryVendors(analytics: NoOpAnalyticsRepository(), crashReporter: NoOpCrashReporter())

    /// Configures Firebase with explicit options only when `settings` is non-nil. Never calls
    /// `FirebaseApp.configure()` without options: that crashes without a GoogleService-Info.plist.
    static func make(settings: FirebaseSettings?) -> TelemetryVendors {
        guard let settings else { return .noOp }
        if FirebaseApp.app() == nil {
            let options = FirebaseOptions(googleAppID: settings.googleAppID, gcmSenderID: settings.gcmSenderID)
            options.apiKey = settings.apiKey
            options.projectID = settings.projectID
            FirebaseApp.configure(options: options)
        }
        return TelemetryVendors(analytics: FirebaseAnalyticsRepository(), crashReporter: FirebaseCrashlyticsCrashReporter())
    }
}
