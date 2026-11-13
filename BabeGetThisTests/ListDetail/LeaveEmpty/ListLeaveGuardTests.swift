import Foundation
import XCTest
@testable import BabeGetThis

/// Stands in for `ShoppingListRepository` on the leave path: `sendShareCode` emits the
/// list's share state, and every delete-if-empty call is recorded.
final class FakeListLeaveCleaner: ListLeaveCleaning, @unchecked Sendable {
    private let lock = NSLock()
    private var current: String??
    private var continuations: [AsyncThrowingStream<String?, any Error>.Continuation] = []
    private var _deleteCalls: [String] = []

    var deleteCalls: [String] { lock.withLock { _deleteCalls } }

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

    func deleteListIfEmpty(listId: String) async throws -> Result<Bool, AppError> {
        lock.withLock { _deleteCalls.append(listId) }
        return .success(true)
    }
}

/// Port of the leave-empty-list cases of Android's ShoppingItemsViewModelTest
/// (`leavingDeletesList` and `onCleared`), plus the dialog's back / stay / confirm flow.
@MainActor
final class ListLeaveGuardTests: XCTestCase {
    private var source: FakeListDetailItemsSource!
    private var cleaner: FakeListLeaveCleaner!
    private var model: ListDetailViewModel!
    private var leaveGuard: ListLeaveGuard!
    private var observers: [Task<Void, Never>] = []

    override func setUp() async throws {
        source = FakeListDetailItemsSource()
        cleaner = FakeListLeaveCleaner()
        model = ListDetailViewModel(listId: "L1", source: source, haptics: SilentHaptics())
        leaveGuard = ListLeaveGuard(listId: "L1", cleaner: cleaner)
    }

    override func tearDown() async throws {
        observers.forEach { $0.cancel() }
        observers = []
    }

    /// Starts observing items and share state, like the screen's `.task`s.
    private func open() {
        let model = model!
        let leaveGuard = leaveGuard!
        observers.append(Task { await model.observeItems() })
        observers.append(Task { await leaveGuard.observeShareCode() })
    }

    private func loaded(items: [StoredShoppingItem], shareCode: String? = nil) async {
        source.send(items)
        cleaner.sendShareCode(shareCode)
        open()
        await listDetailEventually { self.model.hasLoaded }
        await Task.yield()
    }

    // MARK: - leavingDeletesList

    func testLeavingAnEmptyListWouldDeleteIt() async {
        await loaded(items: [])

        await listDetailEventually { self.leaveGuard.leavingDeletesList(self.model) }
    }

    func testLeavingAListWithItemsKeepsIt() async {
        await loaded(items: [TestData.storedItem("1")])
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(leaveGuard.leavingDeletesList(model))
    }

    // Shared lists are never auto-deleted (the partner may still be using them), so
    // asking would be untrue there.
    func testLeavingAnEmptySharedListKeepsIt() async {
        await loaded(items: [], shareCode: "ABC123")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(leaveGuard.leavingDeletesList(model))
    }

    func testAddingTheFirstItemStopsTheQuestion() async {
        await loaded(items: [])
        await listDetailEventually { self.leaveGuard.leavingDeletesList(self.model) }

        source.send([TestData.storedItem("1")])

        await listDetailEventually { !self.leaveGuard.leavingDeletesList(self.model) }
    }

    // Until the database answers, the list's contents are unknown; assuming "empty"
    // would ask on a quick back press from a full list.
    func testNothingIsClaimedBeforeTheItemsHaveLoaded() async {
        cleaner.sendShareCode(nil)
        open()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(leaveGuard.leavingDeletesList(model))
    }

    // MARK: - Back, "Keep editing", "Delete list"

    func testBackOnAnEmptyListAsksInsteadOfLeaving() async {
        await loaded(items: [])
        await listDetailEventually { self.leaveGuard.leavingDeletesList(self.model) }

        XCTAssertFalse(leaveGuard.backTapped(model))
        XCTAssertTrue(leaveGuard.isConfirming)

        leaveGuard.stay()
        XCTAssertFalse(leaveGuard.isConfirming)
        XCTAssertTrue(cleaner.deleteCalls.isEmpty, "keep editing deletes nothing")
    }

    func testBackOnAListWithItemsLeavesStraightAway() async {
        await loaded(items: [TestData.storedItem("1")])

        XCTAssertTrue(leaveGuard.backTapped(model))
        XCTAssertFalse(leaveGuard.isConfirming)
    }

    func testDialogCopyMatchesAndroid() {
        XCTAssertEqual("Delete this empty list?", ListLeaveGuard.title)
        XCTAssertEqual("This list has no items, so it will be deleted when you leave.", ListLeaveGuard.message)
        XCTAssertEqual("Delete list", ListLeaveGuard.confirmTitle)
        XCTAssertEqual("Keep editing", ListLeaveGuard.stayTitle)
    }

    // MARK: - Teardown (Android onCleared)

    // Leaving a list with nothing in it cleans the list up.
    func testTeardownDeletesAListLeftEmpty() async {
        await leaveGuard.tearDown().value

        XCTAssertEqual(["L1"], cleaner.deleteCalls)
    }

    func testTeardownProceedsImmediatelyWhenNoUndoIsInFlight() async {
        await leaveGuard.tearDown().value

        XCTAssertEqual(1, cleaner.deleteCalls.count)
    }

    // The dangerous interleaving: Undo is tapped and the user backs out in the same
    // breath. The teardown waits for the restore BEFORE asking whether the list is
    // empty; without that the check races the restore, sees zero items, and deletes
    // the very list the user just rescued.
    func testTeardownWaitsForAnInFlightUndoBeforeDecidingTheListIsEmpty() async {
        await loaded(items: [TestData.storedItem("a")])
        await model.delete("a")
        let (gate, release) = AsyncStream<Void>.makeStream()

        leaveGuard.trackUndo { [model] in
            for await _ in gate { break }
            await model!.undoDelete()
        }
        let teardown = leaveGuard.tearDown()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(cleaner.deleteCalls.isEmpty, "the restore is still parked, so no emptiness check yet")

        release.yield()
        await teardown.value

        XCTAssertEqual(1, source.restored.count)
        XCTAssertEqual(["L1"], cleaner.deleteCalls)
    }
}

private struct SilentHaptics: HapticPlaying {
    func play(_ haptic: Haptic) {}
}
