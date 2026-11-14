import Foundation
@testable import BabeGetThis

/// Records every analytics call. Thread-safe, since the data-shape refresh runs detached.
final class RecordingAnalytics: AnalyticsRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [AnalyticsEvent] = []
    private var _users: [String?] = []
    private var _collection: [Bool] = []

    var events: [AnalyticsEvent] { lock.withLock { _events } }
    var users: [String?] { lock.withLock { _users } }
    var collection: [Bool] { lock.withLock { _collection } }

    func track(_ event: AnalyticsEvent) { lock.withLock { _events.append(event) } }
    func setUser(_ userId: String?) { lock.withLock { _users.append(userId) } }
    func setCollectionEnabled(_ enabled: Bool) { lock.withLock { _collection.append(enabled) } }
}

/// Records every crash-reporter call.
final class RecordingCrashReporter: CrashReporter, @unchecked Sendable {
    struct KeyValue: Equatable {
        let key: CrashKey
        let value: String
    }

    private let lock = NSLock()
    private var _breadcrumbs: [String] = []
    private var _keys: [KeyValue] = []
    private var _nonFatals: [AppError] = []
    private var _users: [String?] = []
    private var _collection: [Bool] = []

    var breadcrumbs: [String] { lock.withLock { _breadcrumbs } }
    var keys: [KeyValue] { lock.withLock { _keys } }
    var nonFatals: [AppError] { lock.withLock { _nonFatals } }
    var users: [String?] { lock.withLock { _users } }
    var collection: [Bool] { lock.withLock { _collection } }

    func values(for key: CrashKey) -> [String] { keys.filter { $0.key == key }.map(\.value) }

    func breadcrumb(_ message: String) { lock.withLock { _breadcrumbs.append(message) } }
    func setKey(_ key: CrashKey, value: String) { lock.withLock { _keys.append(KeyValue(key: key, value: value)) } }
    func recordNonFatal(_ error: any Error, appError: AppError) { lock.withLock { _nonFatals.append(appError) } }
    func setUser(_ userId: String?) { lock.withLock { _users.append(userId) } }
    func setCollectionEnabled(_ enabled: Bool) { lock.withLock { _collection.append(enabled) } }
}

final class RecordingConsent: TelemetryConsentApplying, @unchecked Sendable {
    private let lock = NSLock()
    private var _applied = 0
    var applied: Int { lock.withLock { _applied } }

    func applyPersisted() { lock.withLock { _applied += 1 } }
}

/// Fixed counts, and how often each was asked for.
final class CountingDataShape: TelemetryDataShapeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _activeCalls = 0
    private var _pendingItemCalls = 0
    private var _pendingListCalls = 0

    var activeCalls: Int { lock.withLock { _activeCalls } }
    var pendingItemCalls: Int { lock.withLock { _pendingItemCalls } }
    var pendingListCalls: Int { lock.withLock { _pendingListCalls } }

    func countActiveItems() async throws -> Int { lock.withLock { _activeCalls += 1 }; return 12 }
    func countPendingItems() async throws -> Int { lock.withLock { _pendingItemCalls += 1 }; return 1 }
    func countPendingLists() async throws -> Int { lock.withLock { _pendingListCalls += 1 }; return 0 }
}

/// A clock the test moves by hand.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Int64 = 0

    var now: Int64 {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }
}

/// A switchable network state.
final class FakeOnline: @unchecked Sendable {
    private let lock = NSLock()
    private var _online = true

    var online: Bool {
        get { lock.withLock { _online } }
        set { lock.withLock { _online = newValue } }
    }
}
