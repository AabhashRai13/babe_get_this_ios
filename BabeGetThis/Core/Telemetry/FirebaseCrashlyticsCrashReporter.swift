@preconcurrency import FirebaseCrashlytics
import Foundation

/// The slice of the Crashlytics SDK the reporter calls, so its behaviour can be tested without
/// configuring Firebase. `Crashlytics` conforms as is.
protocol CrashlyticsClient: AnyObject {
    func log(_ msg: String)
    func setCustomValue(_ value: Any?, forKey key: String)
    func record(error: any Error)
    func setUserID(_ userID: String?)
    func setCrashlyticsCollectionEnabled(_ enabled: Bool)
    func deleteUnsentReports()
}

extension Crashlytics: CrashlyticsClient {}

/// Crashlytics behind `CrashReporter` (port of Android `CrashlyticsCrashReporter`). Uncaught
/// crashes need no code: Crashlytics installs its handlers when Firebase is configured. This
/// makes those reports worth reading. Only use it after Firebase is configured.
struct FirebaseCrashlyticsCrashReporter: CrashReporter {
    private static let appErrorKey = "app_error"

    /// Resolved on each call, so building the reporter touches no SDK.
    private let client: @Sendable () -> any CrashlyticsClient

    init(client: @escaping @Sendable () -> any CrashlyticsClient = { Crashlytics.crashlytics() }) {
        self.client = client
    }

    func breadcrumb(_ message: String) {
        client().log(message)
    }

    func setKey(_ key: CrashKey, value: String) {
        client().setCustomValue(value, forKey: key.key)
    }

    func recordNonFatal(_ error: any Error, appError: AppError) {
        // The filter, applied where no call site can skip it.
        guard ErrorReportingPolicy.shouldReport(appError) else { return }
        let crashlytics = client()
        // Group reports by our classification, not only by stack.
        crashlytics.setCustomValue(appError.kind.name, forKey: Self.appErrorKey)
        crashlytics.record(error: error)
    }

    func setUser(_ userId: String?) {
        // Crashlytics clears the user with an empty string.
        client().setUserID(userId ?? "")
    }

    /// Persisted by the SDK. With collection off, Crashlytics still writes crash reports to disk
    /// and sends them once collection is turned back on, so an opt-out also deletes them: what
    /// happened while the user was opted out never leaves the phone. `applyPersisted()` runs this
    /// at every launch, so reports written after a mid-session opt-out go on the next start.
    func setCollectionEnabled(_ enabled: Bool) {
        let crashlytics = client()
        crashlytics.setCrashlyticsCollectionEnabled(enabled)
        if !enabled { crashlytics.deleteUnsentReports() }
    }
}
