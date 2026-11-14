import Foundation
import XCTest
@testable import BabeGetThis

/// Stands in for `ShoppingListRepository`: `sendShareCode` emits the list's share state, and
/// `isAccount` answers `isAccountList`.
private final class FakeShareStateSource: ListShareStateSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?? = .some(nil)
    private var continuations: [AsyncThrowingStream<String?, any Error>.Continuation] = []
    private var _isAccount = false

    var isAccount: Bool {
        get { lock.withLock { _isAccount } }
        set { lock.withLock { _isAccount = newValue } }
    }

    func sendShareCode(_ code: String?) {
        let targets = lock.withLock {
            current = .some(code)
            return continuations
        }
        for continuation in targets { continuation.yield(code) }
    }

    func shareCode(listId: String) -> AsyncThrowingStream<String?, any Error> {
        AsyncThrowingStream { continuation in
            let initial = lock.withLock {
                continuations.append(continuation)
                return current
            }
            if let initial { continuation.yield(initial) }
        }
    }

    func isAccountList(_ listId: String) async throws -> Bool { isAccount }
}

/// Records every catch-up (Android `coVerify { syncEngine.catchUp(...) }`).
private final class FakeCatchUp: ListCatchingUp, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []

    var calls: [String] { lock.withLock { _calls } }

    func catchUp(listId: String) async throws -> Result<Void, AppError> {
        lock.withLock { _calls.append(listId) }
        return .success(())
    }
}

/// Android `FakeSharedListRemote.changeEvents`: `emit()` signals every open subscription, and
/// open subscriptions are counted so teardown is observable.
///
/// `failNextSubscriptions` makes that many subscriptions end at once with an error (subscribe
/// gave up, or the server closed the channel). `signalJoin` makes each successful subscription
/// yield once, like the real channel's SUBSCRIBED status.
private final class FakeChanges: ListChangesSource, @unchecked Sendable {
    private struct SubscribeFailed: Error {}

    private let lock = NSLock()
    private var continuations: [UUID: AsyncThrowingStream<Void, any Error>.Continuation] = [:]
    private var _subscribeCount = 0
    private var _failNextSubscriptions = 0
    private var _signalJoin = false

    var openSubscriptions: Int { lock.withLock { continuations.count } }
    var subscribeCount: Int { lock.withLock { _subscribeCount } }
    var failNextSubscriptions: Int {
        get { lock.withLock { _failNextSubscriptions } }
        set { lock.withLock { _failNextSubscriptions = newValue } }
    }
    var signalJoin: Bool {
        get { lock.withLock { _signalJoin } }
        set { lock.withLock { _signalJoin = newValue } }
    }

    func emit() {
        let targets = lock.withLock { Array(continuations.values) }
        for continuation in targets { continuation.yield(()) }
    }

    func changes(listId: String) -> AsyncThrowingStream<Void, any Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            let (fails, joins) = lock.withLock {
                _subscribeCount += 1
                if _failNextSubscriptions > 0 {
                    _failNextSubscriptions -= 1
                    return (true, false)
                }
                continuations[id] = continuation
                return (false, _signalJoin)
            }
            if fails {
                continuation.finish(throwing: SubscribeFailed())
                return
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock { self.continuations.removeValue(forKey: id) }
            }
            if joins { continuation.yield(()) }
        }
    }
}

/// Records each re-subscribe wait and returns at once (or, when `blocks`, waits until cancelled).
private final class RecordingSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var _delays: [Duration] = []
    private var _blocks = false

    var delays: [Duration] { lock.withLock { _delays } }
    var blocks: Bool {
        get { lock.withLock { _blocks } }
        set { lock.withLock { _blocks = newValue } }
    }

    func sleep(_ delay: Duration) async throws {
        let blocks = lock.withLock {
            _delays.append(delay)
            return _blocks
        }
        if blocks {
            try await Task.sleep(for: .seconds(3600))
        } else {
            try Task.checkCancellation()
        }
    }
}

/// The 4 realtime cases of Android `ShoppingItemsViewModelTest` (RT-03), plus teardown.
@MainActor
final class RealtimeLifecycleTests: XCTestCase {
    private var shareState: FakeShareStateSource!
    private var syncEngine: FakeCatchUp!
    private var sharedListRemote: FakeChanges!
    private var sleeper: RecordingSleep!
    private var resolvedEngine = 0
    private var resolvedRemote = 0
    private var screen: Task<Void, Never>?

    override func setUp() async throws {
        shareState = FakeShareStateSource()
        syncEngine = FakeCatchUp()
        sharedListRemote = FakeChanges()
        sleeper = RecordingSleep()
        resolvedEngine = 0
        resolvedRemote = 0
    }

    override func tearDown() async throws {
        screen?.cancel()
        screen = nil
    }

    /// Opens the detail screen: runs the lifecycle like the screen's `.task`.
    private func open() {
        let lifecycle = ListRealtimeLifecycle(
            listId: "L1", shareState: shareState,
            catchUp: { [unowned self] in
                resolvedEngine += 1
                return syncEngine
            },
            changes: { [unowned self] in
                resolvedRemote += 1
                return sharedListRemote
            },
            sleep: { [sleeper] in try await sleeper!.sleep($0) })
        screen = Task { await lifecycle.run() }
    }

    /// Lets the lifecycle run long enough that a wrong catch-up or subscribe would have happened.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    // MARK: - Android cases

    func testOpeningASharedListCatchesUpAndReChecksOnEveryRealtimeEvent() async {
        shareState.sendShareCode("ABC234")

        open()
        await listDetailEventually { self.syncEngine.calls == ["L1"] }
        await listDetailEventually { self.sharedListRemote.openSubscriptions == 1 }

        sharedListRemote.emit()
        await listDetailEventually { self.syncEngine.calls.count == 2 }
        sharedListRemote.emit()
        await listDetailEventually { self.syncEngine.calls.count == 3 }
        await settle()
        XCTAssertEqual(syncEngine.calls, ["L1", "L1", "L1"])
    }

    /// Another phone on the same account may have changed it: catch up once.
    /// No realtime subscription for a list nobody else edits live.
    func testOpeningAnUnsharedAccountListCatchesUpOnceWithoutSubscribing() async {
        shareState.isAccount = true

        open()
        await listDetailEventually { self.syncEngine.calls == ["L1"] }

        sharedListRemote.emit()
        await settle()
        XCTAssertEqual(syncEngine.calls, ["L1"])
        XCTAssertEqual(sharedListRemote.subscribeCount, 0)
        XCTAssertEqual(resolvedRemote, 0, "no socket for an unshared list")
    }

    func testALocalOnlyListNeverTouchesTheSyncEngine() async {
        open()
        await settle()

        XCTAssertEqual(syncEngine.calls, [])
        XCTAssertEqual(sharedListRemote.subscribeCount, 0)
        // A guest list never even builds the sync stack, so nothing reaches the network.
        XCTAssertEqual(resolvedEngine, 0)
        XCTAssertEqual(resolvedRemote, 0)
    }

    func testAListSharedWhileOpenStartsSyncingOnTheSpot() async {
        open()
        await settle()
        XCTAssertEqual(syncEngine.calls, [])

        shareState.sendShareCode("ABC234")

        await listDetailEventually { self.syncEngine.calls == ["L1"] }
        await listDetailEventually { self.sharedListRemote.openSubscriptions == 1 }
    }

    // MARK: - Teardown

    func testClosingTheScreenClosesTheChannel() async {
        shareState.sendShareCode("ABC234")
        open()
        await listDetailEventually { self.sharedListRemote.openSubscriptions == 1 }

        screen?.cancel()

        await listDetailEventually { self.sharedListRemote.openSubscriptions == 0 }
        let before = syncEngine.calls.count
        sharedListRemote.emit()
        await settle()
        XCTAssertEqual(syncEngine.calls.count, before)
    }

    func testUnsharingWhileOpenClosesTheChannel() async {
        shareState.sendShareCode("ABC234")
        open()
        await listDetailEventually { self.sharedListRemote.openSubscriptions == 1 }

        shareState.sendShareCode(nil)

        await listDetailEventually { self.sharedListRemote.openSubscriptions == 0 }
        let before = syncEngine.calls.count
        sharedListRemote.emit()
        await settle()
        XCTAssertEqual(syncEngine.calls.count, before)
    }

    func testAnUnrelatedRowChangeDoesNotResubscribe() async {
        shareState.sendShareCode("ABC234")
        open()
        await listDetailEventually { self.sharedListRemote.openSubscriptions == 1 }

        shareState.sendShareCode("ABC234")
        await settle()

        XCTAssertEqual(sharedListRemote.subscribeCount, 1)
        XCTAssertEqual(syncEngine.calls, ["L1"])
    }

    // MARK: - Re-subscribe

    /// A subscription that ends with an error is retried, and the re-join catches up.
    func testAFailedSubscriptionIsRetriedAndTheRejoinCatchesUp() async {
        sharedListRemote.failNextSubscriptions = 1
        sharedListRemote.signalJoin = true
        shareState.sendShareCode("ABC234")

        open()
        // Opening catch-up, then the second subscription's SUBSCRIBED catches up again.
        await listDetailEventually { self.sharedListRemote.subscribeCount == 2 }
        await listDetailEventually { self.sharedListRemote.openSubscriptions == 1 }
        await listDetailEventually { self.syncEngine.calls.count == 2 }
        XCTAssertEqual(sleeper.delays, [.seconds(1)])

        sharedListRemote.emit()
        await listDetailEventually { self.syncEngine.calls.count == 3 }
        await settle()
        XCTAssertEqual(sharedListRemote.subscribeCount, 2, "a live channel isn't re-subscribed")
    }

    func testRepeatedFailuresBackOffUpToThirtySeconds() async {
        sharedListRemote.failNextSubscriptions = 7
        shareState.sendShareCode("ABC234")

        open()
        await listDetailEventually { self.sharedListRemote.openSubscriptions == 1 }

        XCTAssertEqual(sharedListRemote.subscribeCount, 8)
        XCTAssertEqual(sleeper.delays, [1, 2, 4, 8, 16, 30, 30].map { Duration.seconds($0) })
    }

    func testClosingTheScreenStopsRetrying() async {
        sharedListRemote.failNextSubscriptions = 1
        sleeper.blocks = true
        shareState.sendShareCode("ABC234")

        open()
        await listDetailEventually { self.sleeper.delays.count == 1 }

        screen?.cancel()
        await settle()

        XCTAssertEqual(sharedListRemote.subscribeCount, 1)
        XCTAssertEqual(sharedListRemote.openSubscriptions, 0)
    }

    func testResubscribeDelaysAreBoundedBackoff() {
        let delays = (0..<8).map(ListRealtimeLifecycle.resubscribeDelay(attempt:))
        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 30, 30, 30].map { Duration.seconds($0) })
    }
}
