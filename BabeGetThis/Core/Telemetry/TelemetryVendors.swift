@preconcurrency import FirebaseCore
import Foundation
import os

/// The Firebase app settings from Info.plist (filled per environment from Secrets.xcconfig).
/// Staging and Prod use separate Firebase projects; Dev sends nothing (TEL-01).
struct FirebaseSettings: Equatable, Sendable {
    static let googleAppIDKey = "BGTFirebaseGoogleAppID"
    static let gcmSenderIDKey = "BGTFirebaseGCMSenderID"
    static let apiKeyKey = "BGTFirebaseAPIKey"
    static let projectIDKey = "BGTFirebaseProjectID"

    private static let logger = Logger(subsystem: "com.babegetthis.ios", category: "Telemetry")

    let googleAppID: String
    let gcmSenderID: String
    let apiKey: String
    let projectID: String

    /// The settings to configure Firebase with, or nil when it must stay off: always in Dev,
    /// whenever any of the four values is missing or blank, and when the app id or sender id is
    /// malformed. `FirebaseApp.configure(options:)` raises an Objective-C exception on an app id
    /// it rejects, which Swift can't catch, so a bad id must keep Firebase off instead.
    static func resolve(infoDictionary info: [String: Any], environment: AppConfig.Environment) -> FirebaseSettings? {
        guard environment != .dev else { return nil }
        func value(_ key: String) -> String? {
            let raw = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? nil : raw
        }
        guard let googleAppID = value(googleAppIDKey), let gcmSenderID = value(gcmSenderIDKey),
              let apiKey = value(apiKeyKey), let projectID = value(projectIDKey) else { return nil }
        guard isValidGoogleAppID(googleAppID), gcmSenderID.allSatisfy(\.isASCIIDigit) else {
            logger.error("Firebase stays off: \(googleAppIDKey, privacy: .public) or \(gcmSenderIDKey, privacy: .public) is malformed")
            return nil
        }
        return FirebaseSettings(googleAppID: googleAppID, gcmSenderID: gcmSenderID, apiKey: apiKey, projectID: projectID)
    }

    /// An iOS app id as Firebase checks it (`FIRApp validateAppIDFormat:withVersion:`):
    /// `1:<project number>:ios:<hex hashed bundle id>`. An Android (`:android:`) or Web app id
    /// fails here, as does any stray character. Firebase also lets other version numbers through;
    /// none exist yet, and refusing one keeps Firebase off rather than crashing.
    static func isValidGoogleAppID(_ appID: String) -> Bool {
        let parts = appID.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "1", parts[2] == "ios" else { return false }
        return !parts[1].isEmpty && parts[1].allSatisfy(\.isASCIIDigit)
            && !parts[3].isEmpty && parts[3].allSatisfy(\.isASCIIHexDigit)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    /// `isHexDigit` alone also accepts the fullwidth forms.
    var isASCIIHexDigit: Bool { isASCII && isHexDigit }
}

/// The analytics and crash-reporting implementations the app runs with: Firebase when it is
/// configured, no-ops otherwise. The whole vendor commitment is in this type.
struct TelemetryVendors: Sendable {
    let analytics: any AnalyticsRepository
    /// Always behind `PolicyFilteredCrashReporter`, so only Unknown and Database errors are
    /// recorded as non-fatals whichever vendor sits underneath (ERR-03).
    let crashReporter: any CrashReporter

    init(analytics: any AnalyticsRepository, crashReporter: any CrashReporter) {
        self.analytics = analytics
        self.crashReporter = crashReporter is PolicyFilteredCrashReporter
            ? crashReporter : PolicyFilteredCrashReporter(wrapped: crashReporter)
    }

    /// Sends nothing and never touches Firebase.
    static let noOp = TelemetryVendors(analytics: NoOpAnalyticsRepository(), crashReporter: NoOpCrashReporter())

    /// Set once Firebase has been configured. Tracked here rather than asked of
    /// `FirebaseApp.app()`, which logs I-COR000003 whenever the default app doesn't exist yet.
    private static let isConfigured = OSAllocatedUnfairLock(initialState: false)

    /// Configures Firebase with explicit options only when `settings` is non-nil. Never calls
    /// `FirebaseApp.configure()` without options: that crashes without a GoogleService-Info.plist.
    static func make(settings: FirebaseSettings?) -> TelemetryVendors {
        guard let settings else { return .noOp }
        isConfigured.withLock { configured in
            guard !configured else { return }
            let options = FirebaseOptions(googleAppID: settings.googleAppID, gcmSenderID: settings.gcmSenderID)
            options.apiKey = settings.apiKey
            options.projectID = settings.projectID
            FirebaseApp.configure(options: options)
            configured = true
        }
        return TelemetryVendors(analytics: FirebaseAnalyticsRepository(), crashReporter: FirebaseCrashlyticsCrashReporter())
    }
}
