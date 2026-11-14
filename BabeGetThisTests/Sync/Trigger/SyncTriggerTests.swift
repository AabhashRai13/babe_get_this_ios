import SwiftUI
import XCTest
@testable import BabeGetThis

/// Port of Android `SyncTriggerTest` (TRIG-01, TRIG-02). The three triggers are platform
/// callbacks there; here auth states, network and scene phases are fed by hand.
final class SyncTriggerTests: XCTestCase {
    private var engine: TriggerFakeEngine!
    private var authState: TriggerFakeAuthStates!
    private var network: TriggerFakeNetwork!
    private var tasks: TriggerTaskRecorder!
    private var trigger: SyncTrigger!

    override func setUp() async throws {
        try await super.setUp()
        engine = TriggerFakeEngine()
        authState = TriggerFakeAuthStates(.unauthenticated)
        network = TriggerFakeNetwork()
        tasks = TriggerTaskRecorder()
        let engine = engine!
        trigger = SyncTrigger(engine: { engine }, launcher: tasks)
        // The fake network has nothing up, so registering does not fire on its own:
        // each test decides what fires.
        trigger.register(authStates: authState, network: network)
        await tasks.drain()
    }

    func testPushSoonPushesWithoutCatchingUp() async {
        // Repositories kick this after a local edit; the partner's device is
        // the one that pulls, ours already has the data.
        trigger.pushSoon()
        await tasks.drain()

        XCTAssertEqual(engine.pushCount, 1)
        XCTAssertEqual(engine.catchUpAccountCount, 0)
    }

    func testEveryAuthStateIsHandedToTheEngine() async {
        // The engine decides what a state means for this device's lists
        // (claiming, first-run bookkeeping); the trigger only relays it.
        authState.value = .authenticated(userId: "user-1")
        await tasks.drain()

        XCTAssertEqual(engine.authStates, [.unauthenticated, .authenticated(userId: "user-1")])
    }

    func testALiveSessionKicksAPushAndACatchUp() async {
        // Discovery is what materialises the account's lists after login,
        // and login changes neither foreground state nor connectivity.
        engine.answerOnAuthState { $0 == .authenticated(userId: "user-1") }

        authState.value = .authenticated(userId: "user-1")
        await tasks.drain()

        XCTAssertEqual(engine.pushCount, 1)
        XCTAssertEqual(engine.catchUpAccountCount, 1)
    }

    func testAStateWithoutALiveSessionIsNotAKick() async {
        // An expired session would only 401 on every push.
        engine.answerOnAuthState { _ in false }

        authState.value = .sessionExpired(userId: "user-1")
        authState.value = .unauthenticated
        await tasks.drain()

        XCTAssertEqual(engine.pushCount, 0)
        XCTAssertEqual(engine.catchUpAccountCount, 0)
    }

    func testConnectivityReturningKicks() async {
        network.becomeAvailable()
        await tasks.drain()

        XCTAssertEqual(engine.pushCount, 1)
        XCTAssertEqual(engine.catchUpAccountCount, 1)
    }

    func testTheRestOfTheLifecycleIsNotAKick() async {
        // Only becoming active from the background means "foregrounded". Launching
        // (inactive), resigning active and going to the background pass through without one.
        for phase: ScenePhase in [.inactive, .active, .inactive, .background] {
            trigger.scenePhaseChanged(phase)
        }
        await tasks.drain()

        XCTAssertEqual(engine.catchUpAccountCount, 1)
    }

    func testTheAppComingToTheForegroundKicksOncePerForeground() async {
        trigger.scenePhaseChanged(.active)
        // A system sheet or the app switcher (inactive, then active again) is not a
        // new foreground.
        trigger.scenePhaseChanged(.inactive)
        trigger.scenePhaseChanged(.active)
        await tasks.drain()
        XCTAssertEqual(engine.catchUpAccountCount, 1)

        // Backgrounded, then foregrounded again.
        trigger.scenePhaseChanged(.inactive)
        trigger.scenePhaseChanged(.background)
        trigger.scenePhaseChanged(.inactive)
        trigger.scenePhaseChanged(.active)
        await tasks.drain()

        XCTAssertEqual(engine.catchUpAccountCount, 2)
    }

    func testNoEngineMeansNoKickReachesAnything() async {
        // Test containers and -sampleData: sync is off, so a kick has nowhere to go and
        // never builds the engine.
        let resolved = TriggerResolveCounter()
        let off = SyncTrigger(engine: { resolved.hit(); return nil }, launcher: tasks)
        off.register(authStates: TriggerFakeAuthStates(.unauthenticated), network: network)
        off.pushSoon()
        off.scenePhaseChanged(.active)
        await tasks.drain()

        XCTAssertGreaterThan(resolved.count, 0)
        XCTAssertEqual(engine.pushCount, 0)
        XCTAssertEqual(engine.authStates, [.unauthenticated])
    }

    func testAuthManagerStreamStartsWithTheCurrentStateAndFollowsChanges() async {
        let manager = AuthStateManager(tokenStore: InMemoryTokenStore())
        let restored = expectation(description: "restored state delivered")
        let signedIn = expectation(description: "login delivered")
        let seen = TriggerStateLog { states in
            if states == [.loading, .unauthenticated] { restored.fulfill() }
            if states == [.loading, .unauthenticated, .authenticated(userId: "u1")] { signedIn.fulfill() }
        }
        let subscription = manager.observeAuthStates { seen.append($0) }

        await MainActor.run { manager.initialize() }
        await fulfillment(of: [restored], timeout: 2)
        await MainActor.run { manager.login(token: "t", userId: "u1", userName: "U", userEmail: "u@x.y") }
        await fulfillment(of: [signedIn], timeout: 2)
        subscription.cancel()
    }
}

final class TriggerResolveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var hits = 0
    var count: Int { lock.withLock { hits } }
    func hit() { lock.withLock { hits += 1 } }
}

final class TriggerStateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [AuthState] = []
    private let onAppend: @Sendable ([AuthState]) -> Void

    init(onAppend: @escaping @Sendable ([AuthState]) -> Void) {
        self.onAppend = onAppend
    }

    func append(_ state: AuthState) {
        let snapshot = lock.withLock {
            states.append(state)
            return states
        }
        onAppend(snapshot)
    }
}
