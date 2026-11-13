import Foundation
import GRDB
import XCTest
@testable import BabeGetThis

/// A remote hook that parks every caller until `release()`, counting how many
/// are inside it at once.
final class ParkingHook: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var _entries = 0
    private var _active = 0
    private var _maxActive = 0

    var entries: Int { lock.withLock { _entries } }
    var maxActive: Int { lock.withLock { _maxActive } }

    func park() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock {
                _entries += 1
                _active += 1
                _maxActive = max(_maxActive, _active)
                if released { return true }
                parked.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
        lock.withLock { _active -= 1 }
    }

    func release() {
        let waiting = lock.withLock {
            released = true
            defer { parked.removeAll() }
            return parked
        }
        waiting.forEach { $0.resume() }
    }

    /// Waits (bounded) until `count` callers have entered.
    func waitForEntries(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<500 where entries < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThanOrEqual(entries, count, "hook never entered", file: file, line: line)
    }
}

// iOS-only cases (no Android counterpart): the serial gate, and the three
// races iOS closes deliberately (PARITY SYNC-04, SYNC-08, SYNC-10/11).
final class SyncEngineRaceTests: XCTestCase {
    private var db: AppDatabase!
    private var remote: FakeSharedListRemote!
    private var syncPoints: FakeSyncPointStore!
    private var engine: SyncEngine!

    private let t10 = "2026-08-01T10:00:00Z"
    private let t11 = "2026-08-01T11:00:00Z"

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
        remote = FakeSharedListRemote()
        syncPoints = FakeSyncPointStore()
        engine = makeEngine { "user-1" }
    }

    private func makeEngine(currentUserId: @escaping @Sendable () -> String?) -> SyncEngine {
        SyncEngine(
            listDao: db.lists, itemDao: db.items, remote: remote, syncPoints: syncPoints,
            ownership: FakeListOwnershipStore(), currentUserId: currentUserId,
            safeCall: SafeCall(reporter: SilentAppErrorReporter()))
    }

    // MARK: - Helpers

    private func listEntity(
        id: String = "list-1",
        updatedAt: Int64 = 1_000,
        pendingSync: Bool = false,
        onServer: Bool = true
    ) -> ShoppingListRecord {
        ShoppingListRecord(
            id: id, name: "Groceries", createdAt: 500, updatedAt: updatedAt, isLocked: false,
            shareCode: nil, deletedAt: nil, pendingSync: pendingSync, accountId: "user-1", onServer: onServer)
    }

    private func itemEntity(id: String = "item-1", updatedAt: Int64 = 1_000, pendingSync: Bool = false) -> ShoppingItemRecord {
        ShoppingItemRecord(
            id: id, listId: "list-1", name: "Milk", quantity: "1", isPickedUp: false, categoryId: nil,
            shop: nil, note: nil, createdAt: 500, updatedAt: updatedAt, deletedAt: nil, pendingSync: pendingSync)
    }

    private func assertSuccess(_ result: Result<Void, AppError>, file: StaticString = #filePath, line: UInt = #line) {
        if case .failure(let error) = result { XCTFail("expected success, got \(error)", file: file, line: line) }
    }

    // MARK: - Serial gate (SYNC-02)

    func testACatchUpWaitsForAPushInFlight() async throws {
        try await db.lists.insertList(listEntity())
        try await db.items.insertItem(itemEntity(pendingSync: true))
        let hook = ParkingHook()
        remote.onUpsertItems = { await hook.park() }
        let engine = engine!

        let push = Task { try await engine.push() }
        try await hook.waitForEntries(1)
        let catchUp = Task { try await engine.catchUp(listId: "list-1") }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(remote.fetchedListIds.isEmpty, "catch-up ran while the push held the gate")
        hook.release()
        assertSuccess(try await push.value)
        assertSuccess(try await catchUp.value)
        XCTAssertEqual(remote.fetchedListIds, ["list-1"])
    }

    func testTwoPushesNeverOverlap() async throws {
        try await db.lists.insertList(listEntity())
        try await db.items.insertItem(itemEntity(pendingSync: true))
        let hook = ParkingHook()
        remote.onUpsertItems = { await hook.park() }
        let engine = engine!

        let first = Task { try await engine.push() }
        try await hook.waitForEntries(1)
        let second = Task { try await engine.push() }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(hook.entries, 1, "the second push reached the remote while the first held the gate")
        hook.release()
        assertSuccess(try await first.value)
        assertSuccess(try await second.value)
        XCTAssertEqual(hook.maxActive, 1)
        XCTAssertEqual(remote.upsertedItems.map(\.id), ["item-1"], "the second push found nothing left to send")
    }

    // MARK: - fullCatchUp under the gate (SYNC-08)

    func testFullCatchUpPullsFromScratchEvenWithACatchUpInFlight() async throws {
        syncPoints.set(listId: "list-1", iso: t10)
        remote.listRows = [ListRow(
            id: "list-1", name: "Groceries", shareCode: "ABC123", createdBy: "user-1", updatedAt: t11, deletedAt: nil)]
        let hook = ParkingHook()
        remote.onFetchItems = { await hook.park() }
        let engine = engine!

        let inFlight = Task { try await engine.catchUp(listId: "list-1") }
        try await hook.waitForEntries(1)
        let full = Task { try await engine.fullCatchUp(listId: "list-1") }
        try await Task.sleep(for: .milliseconds(100))
        hook.release()
        assertSuccess(try await inFlight.value)
        assertSuccess(try await full.value)

        XCTAssertEqual(remote.fetchedListIds, ["list-1", "list-1"])
        XCTAssertNil(remote.lastListSince, "the in-flight catch-up's mark leaked into the full pull")
        XCTAssertNil(remote.lastItemSince)
    }

    // MARK: - Apply in one transaction (SYNC-10, SYNC-11)

    func testALocalTickCommittedDuringACatchUpIsNotOverwritten() async throws {
        try await db.lists.insertList(listEntity(updatedAt: try t10.isoToMillis()))
        try await db.items.insertItem(itemEntity(updatedAt: try t10.isoToMillis()))
        remote.itemRows = [ItemRow(id: "item-1", listId: "list-1", name: "Oat milk", quantity: "1", updatedAt: t11, deletedAt: nil)]
        let items = db.items
        remote.onFetchItems = {
            try await items.setPickedUp(itemId: "item-1", isPickedUp: true, updatedAt: 5_000, pendingSync: true)
        }

        assertSuccess(try await engine.catchUp(listId: "list-1"))

        let stored = try await db.items.itemRaw(id: "item-1")
        let item = try XCTUnwrap(stored)
        XCTAssertTrue(item.isPickedUp, "the tick was overwritten")
        XCTAssertTrue(item.pendingSync, "the tick will never be pushed")
        XCTAssertEqual(item.name, "Milk")
    }

    func testALocalRenameCommittedDuringACatchUpIsNotOverwritten() async throws {
        try await db.lists.insertList(listEntity(updatedAt: try t10.isoToMillis()))
        remote.listRows = [ListRow(
            id: "list-1", name: "Server name", shareCode: nil, createdBy: "user-1", updatedAt: t11, deletedAt: nil)]
        let writer = db.writer
        remote.onFetchItems = {
            try await writer.write { db in
                try db.execute(sql: "UPDATE shopping_lists SET name = 'Mine', updatedAt = 5000, pendingSync = 1 WHERE id = 'list-1'")
            }
        }

        assertSuccess(try await engine.catchUp(listId: "list-1"))

        let stored = try await db.lists.listRaw(id: "list-1")
        let list = try XCTUnwrap(stored)
        XCTAssertEqual(list.name, "Mine")
        XCTAssertTrue(list.pendingSync)
    }

    // MARK: - Never-sent tombstones (SYNC-04)

    func testPushNeverInsertsAListSoftDeletedAfterTheNeverSentDrop() async throws {
        try await db.lists.insertList(listEntity(updatedAt: 1_000, pendingSync: true, onServer: false))
        try await db.items.insertItem(itemEntity(pendingSync: true))
        // currentUserId() is read between the drop and the pending-lists read:
        // the soft-delete lands exactly in that window, the first time only.
        let writer = db.writer
        let deleted = SyncTestUserId(nil)
        let engine = makeEngine {
            if deleted.value == nil {
                deleted.value = "done"
                try? writer.write { db in
                    try db.execute(sql: """
                        UPDATE shopping_lists SET deletedAt = 2000, updatedAt = 2000, pendingSync = 1 WHERE id = 'list-1'
                        """)
                }
            }
            return "user-1"
        }

        assertSuccess(try await engine.push())

        XCTAssertTrue(remote.insertedLists.isEmpty, "a never-sent tombstone reached the server")
        XCTAssertTrue(remote.upsertedLists.isEmpty)
        XCTAssertTrue(remote.upsertedItems.isEmpty, "items of a never-sent tombstone were pushed")
        let afterFirst = try await db.lists.listRaw(id: "list-1")
        let tombstone = try XCTUnwrap(afterFirst)
        XCTAssertFalse(tombstone.onServer)
        XCTAssertTrue(tombstone.pendingSync, "left pending so the next drop deletes it")

        assertSuccess(try await engine.push())

        let afterSecond = try await db.lists.listRaw(id: "list-1")
        XCTAssertNil(afterSecond, "the next push's drop removes it")
        XCTAssertTrue(remote.insertedLists.isEmpty)
    }
}
