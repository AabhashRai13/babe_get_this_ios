import Foundation

/// Decides which handled errors are worth sending (ERR-03, port of Android `ErrorReportingPolicy`).
/// It works by sending LESS: an offline-first app produces network failures all day, and a
/// dashboard that is 99% "no internet connection" is one nobody opens.
enum ErrorReportingPolicy {
    static func shouldReport(_ error: AppError) -> Bool {
        // Every case is listed, with no `default`, so a new AppError case forces a decision here.
        switch error {
        // safeCall met an error it had no mapping for: the best signal in the set.
        case .unknown: true
        // The local database failed. Never the user's fault, and it may be corrupting data.
        case .database: true

        // Offline-first: ordinary.
        case .network: false
        case .timeout: false
        // The user sees a message and fixes their input.
        case .validation: false
        // Wrong password, expired session, a code that matched no list.
        case .auth: false
        case .unauthorized: false
        case .notFound: false
        // 5xx is visible in the backend's own monitoring; one outage would be thousands of reports.
        case .server: false
        }
    }
}

/// Applies `ErrorReportingPolicy` in front of any crash reporter and forwards everything else
/// (ERR-03). Vendor-neutral, so the filter the app ships is the one the tests run:
/// `TelemetryVendors` wraps every crash reporter in it, Firebase or not.
struct PolicyFilteredCrashReporter: CrashReporter {
    let wrapped: any CrashReporter

    func breadcrumb(_ message: String) {
        wrapped.breadcrumb(message)
    }

    func setKey(_ key: CrashKey, value: String) {
        wrapped.setKey(key, value: value)
    }

    func recordNonFatal(_ error: any Error, appError: AppError) {
        // The filter, applied where no call site can skip it.
        guard ErrorReportingPolicy.shouldReport(appError) else { return }
        wrapped.recordNonFatal(error, appError: appError)
    }

    func setUser(_ userId: String?) {
        wrapped.setUser(userId)
    }

    func setCollectionEnabled(_ enabled: Bool) {
        wrapped.setCollectionEnabled(enabled)
    }
}
