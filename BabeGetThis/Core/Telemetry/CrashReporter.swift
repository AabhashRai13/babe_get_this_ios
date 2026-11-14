import Foundation

/// The only crash-reporting surface feature code may touch (port of Android `CrashReporter`).
/// Kept apart from `AnalyticsRepository` because the two may move to different vendors.
protocol CrashReporter: Sendable {
    /// A step on the path to a failure. Actions and outcomes only: never item names,
    /// transcription text, emails, invite codes or anything else the user wrote.
    func breadcrumb(_ message: String)

    /// State attached to every later report. The key is an enum so the set stays small.
    func setKey(_ key: CrashKey, value: String)

    /// Reports a handled error. Not everything is sent: the implementation applies
    /// `ErrorReportingPolicy`, so no call site can skip the filter.
    func recordNonFatal(_ error: any Error, appError: AppError)

    /// The Supabase user UUID while signed in, nil on sign-out. Nothing else identifying.
    func setUser(_ userId: String?)

    /// The user's opt-out, separate from the analytics switch.
    func setCollectionEnabled(_ enabled: Bool)
}

/// The reproduction state attached to every report. Bounded; nothing here is free-form.
enum CrashKey: String, CaseIterable, Sendable {
    /// Which build (dev, staging, prod).
    case flavor
    /// Signed in or not.
    case authState = "auth_state"
    /// Online or offline at the time.
    case networkState = "network_state"
    /// Pending sync operations, bucketed.
    case syncQueueDepth = "sync_queue_depth"
    /// Active items, bucketed, never exact.
    case itemCountBucket = "item_count_bucket"
    /// Last screen entered, from `Screen`.
    case lastScreen = "last_screen"

    var key: String { rawValue }
}

/// Sends nothing. Used in Dev, when Firebase isn't configured, and by every test.
struct NoOpCrashReporter: CrashReporter {
    func breadcrumb(_ message: String) {}
    func setKey(_ key: CrashKey, value: String) {}
    func recordNonFatal(_ error: any Error, appError: AppError) {}
    func setUser(_ userId: String?) {}
    func setCollectionEnabled(_ enabled: Bool) {}
}
