import Foundation
import XCTest
@testable import BabeGetThis

// Port of the catchUp / fullCatchUp cases of Android `SyncEngineTest`
// (SYNC-07, SYNC-08, SYNC-10, SYNC-11, SYNC-19). A real in-memory database, so
// LWW, the FK guard and the never-REPLACE rule run against real SQL, with a
// fake remote.
final class SyncEngineCatchUpTests: XCTestCase {
    private var db: AppDatabase!
    private var remote: FakeSharedListRemote!
    private var syncPoints: FakeSyncPointStore!
    private var ownership: FakeListOwnershipStore!
    private var userId: SyncTestUserId!
    private var engine: SyncEngine!

    private var listDao: ShoppingListDao { db.lists }
    private var itemDao: ShoppingItemDao { db.items }

    private let t10 = "2026-08-01T10:00:00Z"
    private let t11 = "2026-08-01T11:00:00Z"
    private let t12 = "2026-08-01T12:00:00Z"

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
        remote = FakeSharedListRemote()
        syncPoints = FakeSyncPointStore()
        ownership = FakeListOwnershipStore()
        userId = SyncTestUserId("user-1")
        let userId = userId!
        engine = SyncEngine(
            listDao: db.lists, itemDao: db.items, remote: remote, syncPoints: syncPoints, ownership: ownership,
            currentUserId: { userId.value }, safeCall: SafeCall(reporter: SilentAppErrorReporter()))
    }

    // MARK: - Helpers

    private func millis(_ iso: String) throws -> Int64 {
        try iso.isoToMillis()
    }

    private func listEntity(
        id: String = "list-1",
        shareCode: String? = "ABC123",
        updatedAt: Int64 = 1_000,
        pendingSync: Bool = false,
        deletedAt: Int64? = nil,
        accountId: String? = "user-1",
        onServer: Bool = true
    ) -> ShoppingListRecord {
        ShoppingListRecord(
            id: id, name: "Groceries", createdAt: 500, updatedAt: updatedAt, isLocked: false,
            shareCode: shareCode, deletedAt: deletedAt, pendingSync: pendingSync,
            accountId: accountId, onServer: onServer)
    }

    private func itemEntity(
        id: String = "item-1",
        listId: String = "list-1",
        updatedAt: Int64 = 1_000,
        pendingSync: Bool = false,
        deletedAt: Int64? = nil
    ) -> ShoppingItemRecord {
        ShoppingItemRecord(
            id: id, listId: listId, name: "Milk", quantity: "1", isPickedUp: false, categoryId: nil,
            shop: nil, note: nil, createdAt: 500, updatedAt: updatedAt, deletedAt: deletedAt,
            pendingSync: pendingSync)
    }

    private func listRow(
        id: String = "list-1",
        name: String = "Groceries",
        updatedAt: String? = "2026-08-01T10:00:00Z",
        deletedAt: String? = nil
    ) -> ListRow {
        ListRow(id: id, name: name, shareCode: "ABC123", createdBy: "user-1", updatedAt: updatedAt, deletedAt: deletedAt)
    }

    private func itemRow(
        id: String = "item-1",
        listId: String = "list-1",
        name: String = "Milk",
        updatedAt: String? = "2026-08-01T10:00:00Z",
        deletedAt: String? = nil
    ) -> ItemRow {
        ItemRow(id: id, listId: listId, name: name, quantity: "1", updatedAt: updatedAt, deletedAt: deletedAt)
    }

    private func listRaw(_ id: String) async throws -> ShoppingListRecord? {
        try await listDao.listRaw(id: id)
    }

    private func itemRaw(_ id: String) async throws -> ShoppingItemRecord? {
        try await itemDao.itemRaw(id: id)
    }

    private func assertSuccess(_ result: Result<Void, AppError>, file: StaticString = #filePath, line: UInt = #line) {
        if case .failure(let error) = result { XCTFail("expected success, got \(error)", file: file, line: line) }
    }

    // MARK: - catchUp

    func testCatchUpLandsBrandNewRowsAsCleanWrites() async throws {
        remote.listRows = [listRow()]
        remote.itemRows = [itemRow()]

        let result = try await engine.catchUp(listId: "list-1")

        assertSuccess(result)
        let storedList = try await listRaw("list-1")
        let storedItem = try await itemRaw("item-1")
        let list = try XCTUnwrap(storedList)
        let item = try XCTUnwrap(storedItem)
        XCTAssertEqual(list.updatedAt, try millis(t10))
        XCTAssertFalse(list.pendingSync)
        XCTAssertEqual(item.name, "Milk")
        XCTAssertFalse(item.pendingSync)
    }

    func testCatchUpPassesTheStoredSyncPointAndRecordsTheNewestStamp() async throws {
        syncPoints.set(listId: "list-1", iso: t10)
        remote.listRows = [listRow(updatedAt: t11)]
        remote.itemRows = [itemRow(updatedAt: t12)]

        _ = try await engine.catchUp(listId: "list-1")

        XCTAssertEqual(remote.lastListSince, t10)
        XCTAssertEqual(remote.lastItemSince, t10)
        XCTAssertEqual(syncPoints.get(listId: "list-1"), t12, "newest stamp wins")
    }

    func testCatchUpWithNothingNewLeavesTheSyncPointAlone() async throws {
        _ = try await engine.catchUp(listId: "list-1")

        XCTAssertNil(syncPoints.get(listId: "list-1"))
    }

    func testCatchUpSkipsRowsOlderThanTheLocalCopy() async throws {
        try await listDao.insertList(listEntity(updatedAt: try millis(t12)))
        remote.listRows = [listRow(name: "Stale name", updatedAt: t10)]

        _ = try await engine.catchUp(listId: "list-1")

        let list = try await listRaw("list-1")
        XCTAssertEqual(list?.name, "Groceries")
    }

    // Discovery returns every row on every pass, and gte refetches the row at
    // the sync point: a row already applied must not be written again (each
    // write re-runs the lists screen's query).
    func testCatchUpDoesNotRewriteARowItHasAlreadyApplied() async throws {
        try await listDao.insertList(listEntity(updatedAt: try millis(t10)))
        remote.listRows = [listRow(name: "Same stamp, so already applied", updatedAt: t10)]

        _ = try await engine.catchUp(listId: "list-1")

        let list = try await listRaw("list-1")
        XCTAssertEqual(list?.name, "Groceries")
    }

    func testTombstonesOfRowsThisPhoneNeverHadAreNotStored() async throws {
        remote.listRows = [listRow(id: "gone", updatedAt: t10, deletedAt: t10), listRow()]
        remote.itemRows = [itemRow(id: "gone-item", updatedAt: t11, deletedAt: t11), itemRow(id: "live")]

        // The fake answers fetchList with the requested id only, so the
        // tombstoned list is asked for on its own as well.
        _ = try await engine.catchUp(listId: "gone")
        _ = try await engine.catchUp(listId: "list-1")

        let gone = try await listRaw("gone")
        let goneItem = try await itemRaw("gone-item")
        let live = try await itemRaw("live")
        XCTAssertNil(gone)
        XCTAssertNil(goneItem)
        XCTAssertNotNil(live)
    }

    func testCatchUpNeverOverwritesDirtyLocalRows() async throws {
        try await listDao.insertList(listEntity(updatedAt: 1_000, pendingSync: true))
        remote.listRows = [listRow(name: "Remote name", updatedAt: t12)]

        _ = try await engine.catchUp(listId: "list-1")

        let stored = try await listRaw("list-1")
        let local = try XCTUnwrap(stored)
        XCTAssertEqual(local.name, "Groceries", "our push will out-timestamp it")
        XCTAssertTrue(local.pendingSync)
    }

    // Regression: applying an inbound list row through INSERT OR REPLACE is
    // DELETE + INSERT, which fires shopping_items' ON DELETE CASCADE. One
    // renamed list from a peer wiped that list's items on every device,
    // unrecoverably (hard delete, not a tombstone).
    func testCatchUpApplyingAChangedListRowKeepsTheListsItems() async throws {
        try await listDao.insertList(listEntity(updatedAt: try millis(t10)))
        try await itemDao.insertItem(itemEntity(updatedAt: try millis(t10)))
        remote.listRows = [listRow(name: "Renamed by partner", updatedAt: t12)]

        _ = try await engine.catchUp(listId: "list-1")

        let list = try await listRaw("list-1")
        let item = try await itemRaw("item-1")
        XCTAssertEqual(list?.name, "Renamed by partner")
        XCTAssertNotNil(item, "items must survive a list-row update")
    }

    func testCatchUpSkipsItemsWhoseListIsNotLocalYet() async throws {
        remote.itemRows = [itemRow(listId: "list-elsewhere")]

        let result = try await engine.catchUp(listId: "list-elsewhere")

        assertSuccess(result)
        let item = try await itemRaw("item-1")
        XCTAssertNil(item)
    }

    func testCatchUpIgnoresRowsWithoutAServerStamp() async throws {
        remote.listRows = [listRow(updatedAt: nil)]

        _ = try await engine.catchUp(listId: "list-1")

        let list = try await listRaw("list-1")
        XCTAssertNil(list)
    }

    func testCatchUpAppliesRemoteTombstonesAndHidesTheItem() async throws {
        try await listDao.insertList(listEntity())
        try await itemDao.insertItem(itemEntity())
        remote.itemRows = [itemRow(updatedAt: t11, deletedAt: t11)]

        _ = try await engine.catchUp(listId: "list-1")

        let item = try await itemRaw("item-1")
        let live = try await itemDao.itemsByListIdOnce("list-1")
        XCTAssertNotNil(item?.deletedAt)
        XCTAssertTrue(live.isEmpty)
    }

    func testCatchUpIsIdempotent() async throws {
        remote.listRows = [listRow()]
        remote.itemRows = [itemRow()]

        _ = try await engine.catchUp(listId: "list-1")
        let after = try await itemRaw("item-1")
        _ = try await engine.catchUp(listId: "list-1")

        let again = try await itemRaw("item-1")
        XCTAssertEqual(again, after)
    }

    // MARK: - fullCatchUp

    func testFullCatchUpDropsTheHighWaterMarkAndPullsFromScratch() async throws {
        syncPoints.set(listId: "list-1", iso: t12) // already current: plain catchUp would no-op
        remote.listRows = [listRow(updatedAt: t10)]

        let result = try await engine.fullCatchUp(listId: "list-1")

        assertSuccess(result)
        XCTAssertNil(remote.lastListSince, "since must be dropped for the fetch")
        let list = try await listRaw("list-1")
        XCTAssertEqual(list?.name, "Groceries")
        XCTAssertEqual(syncPoints.get(listId: "list-1"), t10, "mark re-established from what came back")
    }
}
