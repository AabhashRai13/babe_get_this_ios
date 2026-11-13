import XCTest
@testable import BabeGetThis

// The Supabase session is the source of truth for "who is signed in". This observer
// mirrors it into the app's own state (the token store via AuthStateManager) and into
// telemetry identity, from one place and on one signal, so the two can never disagree.
final class SessionObserverTests: XCTestCase {
    private var authState: RecordingSessionAuthStateSink!
    private var telemetry: RecordingSessionTelemetryIdentity!

    override func setUp() {
        super.setUp()
        authState = RecordingSessionAuthStateSink()
        telemetry = RecordingSessionTelemetryIdentity()
    }

    /// Feeds `statuses` through an observer and waits until it has consumed them all.
    private func run(
        _ statuses: [SupabaseSessionStatus],
        sink: (any SessionAuthStateSink)? = nil,
        scheduler: any SessionObserverScheduler = ImmediateSessionObserverScheduler()
    ) async {
        let observer = SessionObserver(authState: sink ?? authState, telemetry: telemetry, scheduler: scheduler)
        let (stream, continuation) = AsyncStream<SupabaseSessionStatus>.makeStream()
        let task = observer.observe(stream)
        continuation.yield(.initializing)
        for status in statuses {
            continuation.yield(status)
        }
        continuation.finish()
        await task.value
    }

    private func authenticated(userId: String?, token: String = "access-1") -> SupabaseSessionStatus {
        .authenticated(accessToken: token, userId: userId)
    }

    func testARotatedAccessTokenIsPersisted() async {
        await run([authenticated(userId: "user-1", token: "access-2")])

        XCTAssertEqual(authState.refreshedTokens, ["access-2"])
    }

    func testTelemetryIdentityFollowsTheSessionUserId() async {
        await run([authenticated(userId: "user-1")])

        XCTAssertEqual(telemetry.changes, ["user-1"])
    }

    func testASessionWithoutAUserStillPersistsTheToken() async {
        await run([authenticated(userId: nil)])

        XCTAssertEqual(authState.refreshedTokens, ["access-1"])
        XCTAssertEqual(telemetry.changes, [nil])
    }

    func testALostSessionExpiresLocallyAndClearsTelemetryIdentity() async {
        // A real manager: expiring keeps the account (and its lists), a logout would not.
        let tokens = InMemoryTokenStore()
        tokens.saveToken("access-1")
        tokens.saveUserId("user-1")
        let manager = AuthStateManager(tokenStore: tokens)
        manager.initialize()

        await run([.notAuthenticated], sink: manager)

        XCTAssertEqual(manager.authState, .sessionExpired(userId: "user-1"))
        XCTAssertEqual(tokens.userId(), "user-1")
        XCTAssertNil(tokens.token())
        XCTAssertEqual(telemetry.changes, [nil])
    }

    func testARefreshFailureIsNotALostSession() async {
        // Offline-first: Supabase keeps retrying, and the user keeps their lists meanwhile.
        await run([.refreshFailure])

        XCTAssertEqual(authState.expireCount, 0)
        XCTAssertTrue(telemetry.changes.isEmpty)
    }

    func testInitializingTouchesNothing() async {
        await run([])

        XCTAssertTrue(authState.refreshedTokens.isEmpty)
        XCTAssertEqual(authState.expireCount, 0)
        XCTAssertTrue(telemetry.changes.isEmpty)
    }

    func testSessionChangesAreHandledOnTheScheduler() async {
        // The token store writes the Keychain, so this must not run on the delivering
        // thread. A manual scheduler shows the hand-off: nothing happens until it runs.
        let scheduler = ManualSessionObserverScheduler()
        await run([authenticated(userId: "user-1")], scheduler: scheduler)

        XCTAssertTrue(authState.refreshedTokens.isEmpty)
        scheduler.runAll()
        XCTAssertEqual(authState.refreshedTokens, ["access-1"])
    }

    func testTheDefaultSchedulerAppliesChangesInOrder() async {
        let queue = DispatchQueue(label: "test.session-observer")
        await run(
            [authenticated(userId: "user-1", token: "a"), authenticated(userId: "user-1", token: "b"), .notAuthenticated],
            scheduler: SerialQueueSessionObserverScheduler(queue: queue)
        )
        queue.sync {}

        XCTAssertEqual(authState.refreshedTokens, ["a", "b"])
        XCTAssertEqual(authState.expireCount, 1)
        XCTAssertEqual(telemetry.changes, ["user-1", "user-1", nil])
    }
}

private final class RecordingSessionAuthStateSink: SessionAuthStateSink, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String] = []
    private var expires = 0

    var refreshedTokens: [String] { lock.withLock { tokens } }
    var expireCount: Int { lock.withLock { expires } }

    func refreshToken(_ token: String) { lock.withLock { tokens.append(token) } }
    func expireSession() { lock.withLock { expires += 1 } }
}

private final class RecordingSessionTelemetryIdentity: SessionTelemetryIdentity, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String?] = []

    var changes: [String?] { lock.withLock { recorded } }

    func onUserChanged(_ userId: String?) { lock.withLock { recorded.append(userId) } }
}

private struct ImmediateSessionObserverScheduler: SessionObserverScheduler {
    func schedule(_ work: @escaping @Sendable () -> Void) { work() }
}

private final class ManualSessionObserverScheduler: SessionObserverScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [@Sendable () -> Void] = []

    func schedule(_ work: @escaping @Sendable () -> Void) { lock.withLock { queued.append(work) } }

    func runAll() {
        let work = lock.withLock {
            defer { queued.removeAll() }
            return queued
        }
        work.forEach { $0() }
    }
}
