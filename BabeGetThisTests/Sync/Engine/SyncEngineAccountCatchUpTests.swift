import Foundation
import XCTest
@testable import BabeGetThis

// Port of Android `SyncEngineAccountCatchUpTest` (SYNC-09, SYNC-17), minus the
// three Got This cases and the list-lock case.
//
// Account-wide catch-up (docs/technical-decisions/008): once every account
// list syncs, two requests per list on every app open doesn't scale. One
// discovery request, one account-wide item request since one sync point, and
// a full pull only for lists new to this phone.
final class SyncEngineAccountCatchUpTests: XCTestCase {
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

    private var accountPoint: String? { syncPoints.get(listId: SyncEngine.accountSyncPoint) }

    private func seedAccountList(_ id: String) async throws {
        try await listDao.insertList(ShoppingListRecord(
            id: id, name: "List \(id)", createdAt: 1, updatedAt: 2, isLocked: false,
            shareCode: nil, deletedAt: nil, pendingSync: false, accountId: "user-1", onServer: true))
    }

    private func listRow(_ id: String, updatedAt: String? = nil, deletedAt: String? = nil, name: String = "Server name")
        -> ListRow {
        ListRow(id: id, name: name, createdBy: "user-1", updatedAt: updatedAt ?? t10, deletedAt: deletedAt)
    }

    private func itemRow(_ id: String, listId: String, updatedAt: String? = nil) -> ItemRow {
        ItemRow(id: id, listId: listId, name: "Milk", quantity: "1", updatedAt: updatedAt ?? t10)
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

    // MARK: - Cases

    func testDiscoveryAddsNewListsWithTheirFullItemHistory() async throws {
        remote.listRows = [listRow("new")]
        remote.itemRows = [itemRow("a", listId: "new"), itemRow("b", listId: "new"), itemRow("c", listId: "new")]

        let result = try await engine.catchUpAccount()

        assertSuccess(result)
        let stored = try await listRaw("new")
        let row = try XCTUnwrap(stored)
        XCTAssertEqual(row.accountId, "user-1")
        XCTAssertTrue(row.onServer)
        XCTAssertEqual(remote.itemFetchListIds, ["new"])
        XCTAssertNil(remote.lastItemSince, "a new list is pulled from the start")
        let items = try await itemDao.itemsByListIdOnce("new")
        XCTAssertEqual(items.count, 3)
    }

    // Joining adds a membership row; the list's own updated_at doesn't move.
    func testAListJoinedOnAnotherPhoneIsDiscoveredEvenWhenOlderThanTheSyncPoint() async throws {
        syncPoints.set(listId: SyncEngine.accountSyncPoint, iso: t12)
        remote.listRows = [listRow("joined", updatedAt: t10)]
        remote.itemRows = [itemRow("old-item", listId: "joined", updatedAt: t10)]

        _ = try await engine.catchUpAccount()

        let list = try await listRaw("joined")
        let item = try await itemRaw("old-item")
        XCTAssertNotNil(list)
        XCTAssertNotNil(item)
    }

    func testKnownListsFetchOnlyItemsChangedSinceTheAccountSyncPoint() async throws {
        try await seedAccountList("known")
        syncPoints.set(listId: SyncEngine.accountSyncPoint, iso: t10)
        remote.listRows = [listRow("known")]
        remote.itemRows = [itemRow("fresh", listId: "known", updatedAt: t11)]

        _ = try await engine.catchUpAccount()

        XCTAssertTrue(remote.itemFetchListIds.isEmpty, "no full pull for a list already here")
        XCTAssertEqual(remote.accountItemSinces, [t10])
        let fresh = try await itemRaw("fresh")
        XCTAssertNotNil(fresh)
        XCTAssertEqual(accountPoint, t11)
    }

    // One request however many lists: the server scopes it to the account the
    // same way discovery is scoped, so no list ids travel in the URL.
    func testKnownListsAreCaughtUpInASingleAccountWideRequest() async throws {
        let ids = (0...50).map { String(format: "list-%02d", $0) }
        for id in ids { try await seedAccountList(id) }
        remote.listRows = ids.map { listRow($0) }
        remote.itemRows = [itemRow("first", listId: "list-00"), itemRow("last", listId: "list-50")]

        _ = try await engine.catchUpAccount()

        XCTAssertEqual(remote.accountItemSinces.count, 1)
        let first = try await itemRaw("first")
        let last = try await itemRaw("last")
        XCTAssertNotNil(first)
        XCTAssertNotNil(last)
    }

    func testTheSyncPointDoesNotMoveWhenTheAccountRequestFails() async throws {
        try await seedAccountList("known")
        syncPoints.set(listId: SyncEngine.accountSyncPoint, iso: t10)
        remote.listRows = [listRow("known", updatedAt: t12)]
        remote.failAccountItems = true

        let result = try await engine.catchUpAccount()

        assertFailure(result)
        XCTAssertEqual(accountPoint, t10, "retried from the same point")
    }

    // Nothing to catch up on yet, and the account-wide request would return
    // every item of every list only for the full pulls to fetch them again.
    func testNoAccountWideItemRequestIsMadeBeforeAnyListIsKnown() async throws {
        remote.listRows = [listRow("new", updatedAt: t11)]
        remote.itemRows = [itemRow("a", listId: "new")]

        _ = try await engine.catchUpAccount()

        XCTAssertTrue(remote.accountItemSinces.isEmpty)
        let item = try await itemRaw("a")
        XCTAssertNotNil(item)
        XCTAssertEqual(accountPoint, t11, "the list rows read first of all still move the point")
    }

    // Known lists first: a change to a new list right after its full pull is
    // then newer than anything the sync point was built from, so the next pass
    // fetches it. Read the other way round, a batch read after the pull could
    // carry the point past that change, and the account pass would skip it for
    // good.
    func testTheAccountWideRequestIsReadBeforeAnyFullPull() async throws {
        try await seedAccountList("known")
        remote.listRows = [listRow("known"), listRow("new")]

        _ = try await engine.catchUpAccount()

        XCTAssertEqual(remote.itemReads, ["account", "items:new"])
    }

    func testTheSyncPointMovesOnAPassWithNoItemChanges() async throws {
        try await seedAccountList("known")
        syncPoints.set(listId: SyncEngine.accountSyncPoint, iso: t10)
        remote.listRows = [listRow("known", updatedAt: t12)]

        _ = try await engine.catchUpAccount()

        XCTAssertEqual(accountPoint, t12)
    }

    func testTombstonedListsFoundByDiscoveryAreNeitherStoredNorPulled() async throws {
        remote.listRows = [listRow("deleted", deletedAt: t10)]
        remote.itemRows = [itemRow("x", listId: "deleted")]

        _ = try await engine.catchUpAccount()

        XCTAssertTrue(remote.itemFetchListIds.isEmpty)
        let list = try await listRaw("deleted")
        XCTAssertNil(list, "a deletion of a list this phone never had is nothing to store")
    }

    func testAKnownListsTombstoneIsApplied() async throws {
        try await seedAccountList("known")
        remote.listRows = [listRow("known", updatedAt: t12, deletedAt: t12)]

        _ = try await engine.catchUpAccount()

        let list = try await listRaw("known")
        XCTAssertNotNil(try XCTUnwrap(list).deletedAt)
    }

    // A request without a session gets an empty answer too (RLS filters, it
    // doesn't fail), and a kick can run before the stored session has loaded:
    // that answer must not throw every first-run claim away.
    func testAnEmptyDiscoveryKeepsTheFirstRunClaims() async throws {
        try await listDao.insertList(ShoppingListRecord(
            id: "claimed", name: "Claimed", createdAt: 1, updatedAt: 2, isLocked: false,
            shareCode: "ABC123", deletedAt: nil, pendingSync: false, accountId: "user-1", onServer: true))
        ownership.setUnverifiedListIds(["claimed"])
        remote.listRows = []

        _ = try await engine.catchUpAccount()

        let list = try await listRaw("claimed")
        XCTAssertEqual(list?.accountId, "user-1")
        XCTAssertEqual(ownership.unverifiedListIds(), ["claimed"])
    }

    // Android SyncEngineClaimTest "first-run claims the server doesn't vouch for
    // are released after discovery". iOS has no claimDeviceLists yet, so the
    // claims are seeded directly: owned by this account and listed as unverified.
    func testFirstRunClaimsTheServerDoesNotVouchForAreReleasedAfterDiscovery() async throws {
        try await listDao.insertList(ShoppingListRecord(
            id: "mine", name: "List mine", createdAt: 1, updatedAt: 2, isLocked: false,
            shareCode: "AAA111", deletedAt: nil, pendingSync: false, accountId: "user-1", onServer: true))
        try await listDao.insertList(ShoppingListRecord(
            id: "stray", name: "List stray", createdAt: 1, updatedAt: 2, isLocked: false,
            shareCode: "BBB222", deletedAt: nil, pendingSync: true, accountId: "user-1", onServer: true))
        // Listed as unverified but owned by another account: releaseClaims only
        // touches rows of the account it was given.
        try await listDao.insertList(ShoppingListRecord(
            id: "theirs", name: "List theirs", createdAt: 1, updatedAt: 2, isLocked: false,
            shareCode: "CCC333", deletedAt: nil, pendingSync: false, accountId: "user-2", onServer: true))
        ownership.setUnverifiedListIds(["mine", "stray", "theirs"])
        remote.listRows = [listRow("mine", name: "List mine")]

        assertSuccess(try await engine.catchUpAccount())

        let mine = try await listRaw("mine")
        XCTAssertEqual(mine?.accountId, "user-1")
        let stray = try await listRaw("stray")
        XCTAssertNotNil(stray)
        XCTAssertNil(stray?.accountId, "not this account's: back to ownerless")
        let theirs = try await listRaw("theirs")
        XCTAssertEqual(theirs?.accountId, "user-2")
        XCTAssertTrue(ownership.unverifiedListIds().isEmpty)

        _ = try await engine.push()
        XCTAssertFalse(remote.upsertedLists.contains { $0.id == "stray" }, "a released stray is never pushed")
        XCTAssertFalse(remote.insertedLists.contains { $0.id == "stray" }, "a released stray is never pushed")
    }

    // Android SyncEngineClaimTest "claims stay until the server actually answers".
    func testClaimsStayUntilTheServerActuallyAnswers() async throws {
        try await listDao.insertList(ShoppingListRecord(
            id: "stray", name: "List stray", createdAt: 1, updatedAt: 2, isLocked: false,
            shareCode: "BBB222", deletedAt: nil, pendingSync: false, accountId: "user-1", onServer: true))
        ownership.setUnverifiedListIds(["stray"])
        remote.listRows = [listRow("mine")]
        remote.failFetches = true

        assertFailure(try await engine.catchUpAccount())

        let stray = try await listRaw("stray")
        XCTAssertEqual(stray?.accountId, "user-1")
        XCTAssertEqual(ownership.unverifiedListIds(), ["stray"])
    }

    // A shared replica whose owner was lost before lists had owners: the server
    // returning it for this account is the proof of membership.
    func testAnOrphanedReplicaIsClaimedWhenDiscoveryReturnsItEvenIfDirty() async throws {
        try await listDao.insertList(ShoppingListRecord(
            id: "orphan", name: "Local name", createdAt: 1, updatedAt: 5_000_000_000_000, isLocked: false,
            shareCode: "ABC123", deletedAt: nil, pendingSync: true, accountId: nil, onServer: true))
        remote.listRows = [listRow("orphan", name: "Server name")]

        _ = try await engine.catchUpAccount()

        let stored = try await listRaw("orphan")
        let row = try XCTUnwrap(stored)
        XCTAssertEqual(row.accountId, "user-1")
        XCTAssertEqual(row.name, "Local name", "the unpushed local edit still wins")
        XCTAssertTrue(row.pendingSync)
    }

    func testCatchUpIsANoOpWithoutALiveSession() async throws {
        userId.value = nil
        remote.listRows = [listRow("new")]

        assertSuccess(try await engine.catchUpAccount())
        assertSuccess(try await engine.catchUp(listId: "new"))

        let list = try await listRaw("new")
        XCTAssertNil(list)
        XCTAssertTrue(remote.fetchedListIds.isEmpty)
    }

    // If a new list's row landed before its history, a failed pull would make
    // it "known" next time, and only items newer than the account sync point
    // would ever arrive — the rest of a list joined elsewhere, gone for good.
    func testANewListWhoseHistoryFailsToLoadIsRetriedInFull() async throws {
        syncPoints.set(listId: SyncEngine.accountSyncPoint, iso: t12)
        remote.listRows = [listRow("joined")]
        remote.itemRows = [itemRow("old-item", listId: "joined", updatedAt: t10)]
        remote.failItemFetchFor = "joined"

        assertFailure(try await engine.catchUpAccount())
        let early = try await listRaw("joined")
        XCTAssertNil(early, "no row without its history")

        remote.failItemFetchFor = nil
        _ = try await engine.catchUpAccount()

        let item = try await itemRaw("old-item")
        XCTAssertNotNil(item)
    }
}
