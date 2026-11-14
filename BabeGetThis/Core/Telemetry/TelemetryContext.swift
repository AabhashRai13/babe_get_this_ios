import Foundation

/// The counts behind the data-shape crash keys. The app reads the DAOs directly (Android does
/// too): a COUNT per refresh is cheaper than holding UI-shaped observations for two numbers.
protocol TelemetryDataShapeSource: Sendable {
    func countActiveItems() async throws -> Int
    func countPendingItems() async throws -> Int
    func countPendingLists() async throws -> Int
}

struct DatabaseTelemetryDataShape: TelemetryDataShapeSource {
    let items: ShoppingItemDao
    let lists: ShoppingListDao

    func countActiveItems() async throws -> Int { try await items.countActiveItems() }
    func countPendingItems() async throws -> Int { try await items.countPendingSync() }
    func countPendingLists() async throws -> Int { try await lists.countPendingSync() }
}

/// Keeps the ambient state on reports current: who the user is, where they are, and what shape
/// their data is in (port of Android `TelemetryContext`). A crash report should answer what a
/// triaging engineer would otherwise have to ask the user: which build, signed in or not,
/// online or not, how much data, how far behind sync was.
final class TelemetryContext: Sendable {
    private static let signedIn = "signed_in"
    private static let signedOut = "signed_out"
    private static let online = "online"
    private static let offline = "offline"

    /// How often the data-shape keys are re-counted: one burst of navigation, one set of queries.
    static let dataShapeRefreshWindowMillis: Int64 = 30_000

    private let analytics: any AnalyticsRepository
    private let crashReporter: any CrashReporter
    private let isOnline: @Sendable () -> Bool
    private let consent: any TelemetryConsentApplying
    private let dataShape: any TelemetryDataShapeSource
    private let flavor: String
    private let dataShapeRefresh: Throttle

    init(analytics: any AnalyticsRepository, crashReporter: any CrashReporter,
         isOnline: @escaping @Sendable () -> Bool, consent: any TelemetryConsentApplying,
         dataShape: any TelemetryDataShapeSource, flavor: String,
         dataShapeRefresh: Throttle = Throttle(windowMillis: TelemetryContext.dataShapeRefreshWindowMillis)) {
        self.analytics = analytics
        self.crashReporter = crashReporter
        self.isOnline = isOnline
        self.consent = consent
        self.dataShape = dataShape
        self.flavor = flavor
        self.dataShapeRefresh = dataShapeRefresh
    }

    /// Once, at app start. Consent first: a user who opted out last run must not have this
    /// launch collected. Only the genuinely static key belongs here.
    func onAppStart() {
        consent.applyPersisted()
        crashReporter.setKey(.flavor, value: flavor)
        crashReporter.setKey(.authState, value: Self.signedOut)
    }

    /// Driven by one auth signal, so analytics and crash identity can never disagree.
    /// The id is the Supabase user UUID and nothing else.
    func onUserChanged(_ userId: String?) {
        analytics.setUser(userId)
        crashReporter.setUser(userId)
        crashReporter.setKey(.authState, value: userId == nil ? Self.signedOut : Self.signedIn)
        crashReporter.breadcrumb(userId == nil ? "auth: signed out" : "auth: signed in")
    }

    /// The single navigation hook. Takes a `Screen`, never a title: list titles are user-authored.
    /// Returns the data-shape refresh it started, if any, so tests can wait for it.
    @discardableResult
    func onScreen(_ screen: Screen) -> Task<Void, Never>? {
        analytics.track(.screenViewed(screen))
        crashReporter.breadcrumb("screen: \(screen.screenName)")
        crashReporter.setKey(.lastScreen, value: screen.screenName)
        crashReporter.setKey(.networkState, value: isOnline() ? Self.online : Self.offline)
        return refreshDataShape()
    }

    /// Throttled: three COUNT queries, and navigation can fire several times a second. The keys
    /// are bucketed, so a window's staleness costs nothing. Failure is silent on purpose:
    /// telemetry must never break the app it watches.
    private func refreshDataShape() -> Task<Void, Never>? {
        guard dataShapeRefresh.tryAcquire() else { return nil }
        return Task.detached { [crashReporter, dataShape] in
            do {
                crashReporter.setKey(.itemCountBucket, value: Buckets.count(try await dataShape.countActiveItems()))
                // Lists and items go through the same engine, so "not synced yet" is the total.
                let pending = try await dataShape.countPendingItems() + dataShape.countPendingLists()
                crashReporter.setKey(.syncQueueDepth, value: Buckets.count(pending))
            } catch {}
        }
    }
}
