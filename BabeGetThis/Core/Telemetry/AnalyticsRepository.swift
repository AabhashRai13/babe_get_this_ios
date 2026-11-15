import Foundation

/// The only analytics surface feature code may touch (port of Android `AnalyticsRepository`).
/// Firebase sits behind it, so moving to another vendor is one new implementation and one line
/// in `TelemetryVendors`.
protocol AnalyticsRepository: Sendable {
    /// Records that something happened. See `AnalyticsEvent` for the whole catalog.
    func track(_ event: AnalyticsEvent)

    /// The Supabase user UUID while signed in, nil on sign-out. Never an email or a name.
    func setUser(_ userId: String?)

    /// The user's opt-out, applied at the vendor: only the SDK can actually stop collecting.
    func setCollectionEnabled(_ enabled: Bool)
}

/// Sends nothing. Used in Dev, when Firebase isn't configured, and by every test.
struct NoOpAnalyticsRepository: AnalyticsRepository {
    func track(_ event: AnalyticsEvent) {}
    func setUser(_ userId: String?) {}
    func setCollectionEnabled(_ enabled: Bool) {}
}
