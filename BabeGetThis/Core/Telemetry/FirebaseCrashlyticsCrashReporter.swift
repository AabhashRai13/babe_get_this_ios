@preconcurrency import FirebaseCrashlytics
import Foundation

/// Crashlytics behind `CrashReporter` (port of Android `CrashlyticsCrashReporter`). Uncaught
/// crashes need no code: Crashlytics installs its handlers when Firebase is configured. This
/// makes those reports worth reading. Only use it after Firebase is configured.
struct FirebaseCrashlyticsCrashReporter: CrashReporter {
    private static let appErrorKey = "app_error"

    private var crashlytics: Crashlytics { Crashlytics.crashlytics() }

    func breadcrumb(_ message: String) {
        crashlytics.log(message)
    }

    func setKey(_ key: CrashKey, value: String) {
        crashlytics.setCustomValue(value, forKey: key.key)
    }

    func recordNonFatal(_ error: any Error, appError: AppError) {
        // The filter, applied where no call site can skip it.
        guard ErrorReportingPolicy.shouldReport(appError) else { return }
        // Group reports by our classification, not only by stack.
        crashlytics.setCustomValue(appError.kind.name, forKey: Self.appErrorKey)
        crashlytics.record(error: error)
    }

    func setUser(_ userId: String?) {
        // Crashlytics clears the user with an empty string.
        crashlytics.setUserID(userId ?? "")
    }

    /// Persisted by the SDK.
    func setCollectionEnabled(_ enabled: Bool) {
        crashlytics.setCrashlyticsCollectionEnabled(enabled)
    }
}
