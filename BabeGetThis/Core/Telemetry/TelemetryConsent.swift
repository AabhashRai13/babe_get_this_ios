import Foundation

/// What `TelemetryContext` needs from consent at launch, so its tests can fake it.
protocol TelemetryConsentApplying: Sendable {
    func applyPersisted()
}

/// The user's say over what leaves the device (TEL-02, port of Android `TelemetryConsent`).
///
/// Two independent switches, both on by default (opt-out). The choice is stored in F42's
/// `TelemetryConsentStore` and applied at the vendor on every change, because only the SDK can
/// really stop collecting. The store is display state; `applyPersisted()` pushes it down to the
/// SDKs at launch rather than trusting them to remember.
///
/// It is also a `TelemetryConsentStore`, so a screen given this object instead of the plain
/// store applies a toggle immediately.
final class TelemetryConsent: TelemetryConsentApplying, TelemetryConsentStore, @unchecked Sendable {
    private let store: any TelemetryConsentStore
    private let analytics: any AnalyticsRepository
    private let crashReporter: any CrashReporter
    private let lock = NSLock()

    init(store: any TelemetryConsentStore = UserDefaultsTelemetryConsentStore(),
         analytics: any AnalyticsRepository, crashReporter: any CrashReporter) {
        self.store = store
        self.analytics = analytics
        self.crashReporter = crashReporter
    }

    var analyticsEnabled: Bool {
        get { lock.withLock { store.analyticsEnabled } }
        set { setAnalyticsEnabled(newValue) }
    }

    var crashReportingEnabled: Bool {
        get { lock.withLock { store.crashReportingEnabled } }
        set { setCrashReportingEnabled(newValue) }
    }

    func setAnalyticsEnabled(_ enabled: Bool) {
        lock.withLock { store.analyticsEnabled = enabled }
        analytics.setCollectionEnabled(enabled)
    }

    func setCrashReportingEnabled(_ enabled: Bool) {
        lock.withLock { store.crashReportingEnabled = enabled }
        crashReporter.setCollectionEnabled(enabled)
    }

    /// Re-asserts the stored choice at startup, before anything is recorded. Redundant while
    /// Firebase persists its own flags, but a privacy control shouldn't lean on that.
    func applyPersisted() {
        analytics.setCollectionEnabled(analyticsEnabled)
        crashReporter.setCollectionEnabled(crashReportingEnabled)
    }
}
