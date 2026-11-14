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
private final class FakeChanges: ListChangesSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncThrowingStream<Void, any Error>.Continuation] = [:]
    private var _subscribeCount = 0

    var openSubscriptions: Int { lock.withLock { continuations.count } }
    var subscribeCount: Int { lock.withLock { _subscribeCount } }

    func emit() {
        let targets = lock.withLock { Array(continuations.values) }
        for continuation in targets { continuation.yield(()) }
    }

    func changes(listId: String) -> AsyncThrowingStream<Void, any Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            lock.withLock {
                continuations[id] = continuation
                _subscribeCount += 1
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock { self.continuations.removeValue(forKey: id) }
            }
        }
    }
}

/// The 4 realtime cases of Android `ShoppingItemsViewModelTest` (RT-03), plus teardown.
@MainActor
final class RealtimeLifecycleTests: XCTestCase {
    private var shareState: FakeShareStateSource!
    private var syncEngine: FakeCatchUp!
    private var sharedListRemote: FakeChanges!
    private var resolvedEngine = 0
    private var resolvedRemote = 0
    private var screen: Task<Void, Never>?

    override func setUp() async throws {
        shareState = FakeShareStateSource()
        syncEngine = FakeCatchUp()
        sharedListRemote = FakeChanges()
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
            })
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
}
