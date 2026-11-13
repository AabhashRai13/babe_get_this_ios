import Foundation
import XCTest
@testable import BabeGetThis

/// The signed-in user the engine sees; tests flip it to nil for "signed out".
final class SyncTestUserId: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?

    init(_ userId: String?) { current = userId }

    var value: String? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

// Port of the push / outbox / unsynced cases of Android `SyncEngineTest` (SYNC-16).
// A real in-memory database, so LWW and the guarded flag-clears are exercised
// against real SQL, with a fake remote.
final class SyncEnginePushTests: XCTestCase {
    private var db: AppDatabase!
    private var remote: FakeSharedListRemote!
    private var syncPoints: FakeSyncPointStore!
    private var ownership: FakeListOwnershipStore!
    private var userId: SyncTestUserId!
    private var engine: SyncEngine!

    private var listDao: ShoppingListDao { db.lists }
    private var itemDao: ShoppingItemDao { db.items }

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

    private func listRaw(_ id: String) async throws -> ShoppingListRecord? {
        try await listDao.listRaw(id: id)
    }

    private func itemRaw(_ id: String) async throws -> ShoppingItemRecord? {
        try await itemDao.itemRaw(id: id)
    }

    private func assertSuccess(_ result: Result<Void, AppError>, file: StaticString = #filePath, line: UInt = #line) {
        if case .failure(let error) = result { XCTFail("expected success, got \(error)", file: file, line: line) }
    }

    private func assertFailure(_ result: Result<Void, AppError>, file: StaticString = #filePath, line: UInt = #line) {
        if case .success = result { XCTFail("expected an error", file: file, line: line) }
    }

    // MARK: - push

    func testPushUploadsDirtySharedRowsAndClearsTheirFlags() async throws {
        try await listDao.insertList(listEntity(pendingSync: true))
        try await itemDao.insertItem(itemEntity(pendingSync: true))

        let result = try await engine.push()

        assertSuccess(result)
        XCTAssertEqual(remote.upsertedLists.map(\.id), ["list-1"])
        XCTAssertTrue(remote.insertedLists.isEmpty, "already on the server: upsert, not insert")
        XCTAssertEqual(remote.upsertedItems.map(\.id), ["item-1"])
        let list = try await listRaw("list-1")
        let item = try await itemRaw("item-1")
        XCTAssertEqual(list?.pendingSync, false)
        XCTAssertEqual(item?.pendingSync, false)
    }

    func testPushSendsNothingWhenSignedOutAndKeepsTheQueue() async throws {
        userId.value = nil
        try await listDao.insertList(listEntity(pendingSync: true))

        _ = try await engine.push()

        XCTAssertTrue(remote.upsertedLists.isEmpty)
        let list = try await listRaw("list-1")
        XCTAssertEqual(list?.pendingSync, true)
    }

    func testGuestListsAreNeverPushed() async throws {
        try await listDao.insertList(listEntity(shareCode: nil, pendingSync: true, accountId: nil, onServer: false))
        try await itemDao.insertItem(itemEntity(pendingSync: true))

        _ = try await engine.push()

        XCTAssertTrue(remote.insertedLists.isEmpty)
        XCTAssertTrue(remote.upsertedLists.isEmpty)
        XCTAssertTrue(remote.upsertedItems.isEmpty)
    }

    // MARK: - push: every account list, shared or not (docs/technical-decisions/008)

    func testAListNotYetOnTheServerIsInsertedThenMarkedOnServer() async throws {
        try await listDao.insertList(listEntity(shareCode: nil, pendingSync: true, onServer: false))
        try await itemDao.insertItem(itemEntity(pendingSync: true))

        let result = try await engine.push()

        assertSuccess(result)
        XCTAssertEqual(remote.insertedLists.map(\.id), ["list-1"])
        XCTAssertEqual(remote.insertedLists.count, 1)
        XCTAssertNil(remote.insertedLists.first?.shareCode)
        XCTAssertTrue(remote.upsertedLists.isEmpty, "a brand-new row can't be upserted (RLS)")
        let stored = try await listRaw("list-1")
        let row = try XCTUnwrap(stored)
        XCTAssertTrue(row.onServer)
        XCTAssertFalse(row.pendingSync)
        XCTAssertEqual(remote.upsertedItems.map(\.id), ["item-1"])
    }

    // A previous push reached the server but the app died before recording it,
    // and the row may have changed since (renamed, deleted): the version on the
    // server is the OLD one, so the duplicate goes through the upsert like any
    // row already there. Clearing its flag on the strength of the first INSERT
    // would leave the server on that first version for good.
    func testAnInsertThatFindsTheRowAlreadyThereUpsertsItInTheSamePush() async throws {
        try await listDao.insertList(listEntity(shareCode: nil, pendingSync: true, onServer: false))
        remote.listAlreadyExists = true

        let result = try await engine.push()

        assertSuccess(result)
        XCTAssertEqual(remote.upsertedLists.map(\.id), ["list-1"])
        let stored = try await listRaw("list-1")
        let row = try XCTUnwrap(stored)
        XCTAssertTrue(row.onServer)
        XCTAssertFalse(row.pendingSync)
    }

    // A list created and deleted before any push: nobody else can have it, so
    // its tombstone would only create a permanent server row (plus membership
    // and items) that every discovery returns forever.
    func testAListDeletedBeforeItReachedTheServerIsDroppedNotUploaded() async throws {
        try await listDao.insertList(
            listEntity(shareCode: nil, pendingSync: true, deletedAt: 2_000, onServer: false))
        try await itemDao.insertItem(itemEntity(pendingSync: true))

        _ = try await engine.push()

        XCTAssertTrue(remote.insertedLists.isEmpty)
        XCTAssertTrue(remote.upsertedLists.isEmpty)
        XCTAssertTrue(remote.upsertedItems.isEmpty)
        let list = try await listRaw("list-1")
        let item = try await itemRaw("item-1")
        XCTAssertNil(list)
        XCTAssertNil(item, "CASCADE took the items")
    }

    func testADeletionThatNeverReachedTheServerIsDroppedEvenWithoutASession() async throws {
        userId.value = nil
        try await listDao.insertList(
            listEntity(shareCode: nil, pendingSync: true, deletedAt: 2_000, onServer: false))

        _ = try await engine.push()

        let list = try await listRaw("list-1")
        XCTAssertNil(list)
    }

    func testADeletionOfAListAlreadyOnTheServerIsUploadedAsATombstone() async throws {
        try await listDao.insertList(listEntity(shareCode: nil, pendingSync: true, deletedAt: 2_000, onServer: true))

        _ = try await engine.push()

        XCTAssertEqual(remote.upsertedLists.map(\.id), ["list-1"])
        XCTAssertEqual(remote.upsertedLists.count, 1)
        XCTAssertNotNil(remote.upsertedLists.first?.deletedAt)
        let list = try await listRaw("list-1")
        XCTAssertNotNil(list)
    }

    func testAFailedInsertLeavesTheListOffTheServerAndQueued() async throws {
        try await listDao.insertList(listEntity(shareCode: nil, pendingSync: true, onServer: false))
        remote.failUpserts = true

        let result = try await engine.push()

        assertFailure(result)
        let stored = try await listRaw("list-1")
        let row = try XCTUnwrap(stored)
        XCTAssertFalse(row.onServer)
        XCTAssertTrue(row.pendingSync)
    }

    func testAnotherAccountsPendingListsAndItemsAreNotPushed() async throws {
        try await listDao.insertList(listEntity(id: "theirs", pendingSync: true, accountId: "user-2"))
        try await itemDao.insertItem(itemEntity(id: "their-item", listId: "theirs", pendingSync: true))

        _ = try await engine.push()

        XCTAssertTrue(remote.upsertedLists.isEmpty)
        XCTAssertTrue(remote.upsertedItems.isEmpty)
        let list = try await listRaw("theirs")
        XCTAssertEqual(list?.pendingSync, true)
    }

    func testPushFailureKeepsEveryFlagSet() async throws {
        try await listDao.insertList(listEntity(pendingSync: true))
        remote.failUpserts = true

        let result = try await engine.push()

        assertFailure(result)
        let list = try await listRaw("list-1")
        XCTAssertEqual(list?.pendingSync, true)
    }

    func testPushFailureAfterListsKeepsItemFlagsButClearsListFlags() async throws {
        try await listDao.insertList(listEntity(pendingSync: true))
        try await itemDao.insertItem(itemEntity(pendingSync: true))
        remote.failItemUpserts = true

        let result = try await engine.push()

        assertFailure(result)
        let list = try await listRaw("list-1")
        let item = try await itemRaw("item-1")
        XCTAssertEqual(list?.pendingSync, false, "lists made it up")
        XCTAssertEqual(item?.pendingSync, true, "items retry next kick")
    }

    func testPushDoesNotClearTheFlagOfARowEditedMidPush() async throws {
        try await listDao.insertList(listEntity())
        try await itemDao.insertItem(itemEntity(updatedAt: 1_000, pendingSync: true))
        let itemDao = itemDao
        let newerEdit = itemEntity(updatedAt: 2_000, pendingSync: true)
        remote.onUpsertItems = {
            // A concurrent local edit lands while the batch is in flight.
            try await itemDao.insertItem(newerEdit)
        }

        _ = try await engine.push()

        let item = try await itemRaw("item-1")
        XCTAssertEqual(item?.pendingSync, true, "newer edit must stay queued")
    }

    func testPushSendsTombstonesLikeAnyOtherEdit() async throws {
        try await listDao.insertList(listEntity())
        try await itemDao.insertItem(itemEntity())
        try await itemDao.softDeleteItem(id: "item-1", now: 2_000)

        _ = try await engine.push()

        XCTAssertEqual(remote.upsertedItems.count, 1)
        XCTAssertNotNil(remote.upsertedItems.first?.deletedAt)
        let item = try await itemRaw("item-1")
        XCTAssertEqual(item?.pendingSync, false)
    }

    // MARK: - hasUnsyncedChanges

    func testUnsyncedChangesAreReportedUntilTheyArePushed() async throws {
        try await listDao.insertList(listEntity())
        var unsynced = try await engine.hasUnsyncedChanges(accountId: "user-1")
        XCTAssertFalse(unsynced)

        try await itemDao.insertItem(itemEntity(pendingSync: true))
        unsynced = try await engine.hasUnsyncedChanges(accountId: "user-1")
        XCTAssertTrue(unsynced)

        _ = try await engine.push()
        unsynced = try await engine.hasUnsyncedChanges(accountId: "user-1")
        XCTAssertFalse(unsynced)
    }

    func testAQueuedListEditCountsAsUnsynced() async throws {
        try await listDao.insertList(listEntity(pendingSync: true))

        let unsynced = try await engine.hasUnsyncedChanges(accountId: "user-1")
        XCTAssertTrue(unsynced)
    }

    // A released first-run claim or another account's leftover is pending but
    // can never be pushed by this account: warning about it on every sign-out
    // would be a warning nothing could ever clear.
    func testRowsThisAccountCanNeverPushDoNotCountAsUnsynced() async throws {
        try await listDao.insertList(listEntity(id: "stray", pendingSync: true, accountId: nil))
        try await itemDao.insertItem(itemEntity(id: "stray-item", listId: "stray", pendingSync: true))
        try await listDao.insertList(listEntity(id: "theirs", pendingSync: true, accountId: "user-2"))

        let unsynced = try await engine.hasUnsyncedChanges(accountId: "user-1")
        XCTAssertFalse(unsynced)
    }
}
