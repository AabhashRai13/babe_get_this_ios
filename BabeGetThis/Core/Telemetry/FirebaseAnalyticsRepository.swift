import FirebaseAnalytics
import Foundation
import os

/// Firebase Analytics behind `AnalyticsRepository`. With `FirebaseCrashlyticsCrashReporter` and
/// `TelemetryVendors`, one of the only files allowed to import Firebase. Linked as
/// `FirebaseAnalyticsCore` (no ad-id support): no AdSupport, no IDFA, no ATT prompt (TEL-05).
///
/// Thin on purpose: the mapping lives in `AnalyticsEventMapper`. The SDK queues and uploads
/// on its own schedule, so there is no queue here. Only use it after Firebase is configured.
struct FirebaseAnalyticsRepository: AnalyticsRepository {
    private static let logger = Logger(subsystem: "com.babegetthis.ios", category: "Analytics")

    func track(_ event: AnalyticsEvent) {
        let mapped = AnalyticsEventMapper.map(event)
        var parameters: [String: Any] = [:]
        for (key, value) in mapped.text { parameters[key] = value }
        for (key, value) in mapped.numbers { parameters[key] = NSNumber(value: value) }
        Analytics.logEvent(mapped.name, parameters: parameters.isEmpty ? nil : parameters)
        #if DEBUG
        // GA4 reports lag up to a day; a local echo shortens "did I wire this right?".
        let echo = "\(mapped.name) \(mapped.text) \(mapped.numbers)"
        Self.logger.debug("\(echo, privacy: .public)")
        #endif
    }

    func setUser(_ userId: String?) {
        Analytics.setUserID(userId)
    }

    /// The SDK persists this itself; `TelemetryConsent` re-applies it at every launch anyway.
    func setCollectionEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }
}
