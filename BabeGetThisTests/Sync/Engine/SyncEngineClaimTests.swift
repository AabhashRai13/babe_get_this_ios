import Foundation
import XCTest
@testable import BabeGetThis

// Port of Android `SyncEngineClaimTest` (ACCT-02, ACCT-03, ACCT-04, ACCT-08),
// minus the four Got This cases and the two list-lock cases.
//
// Claiming the device's lists for the account that just signed in
// (docs/technical-decisions/008). Real in-memory database: the claim is SQL,
// and the item flags and the CASCADE are what matter.
final class SyncEngineClaimTests: XCTestCase {
    private var db: AppDatabase!
    private var remote: FakeSharedListRemote!
    private var syncPoints: FakeSyncPointStore!
    private var ownership: FakeListOwnershipStore!
    private var engine: SyncEngine!

    private var listDao: ShoppingListDao { db.lists }
    private var itemDao: ShoppingItemDao { db.items }

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
        remote = FakeSharedListRemote()
        syncPoints = FakeSyncPointStore()
        ownership = FakeListOwnershipStore()
        engine = SyncEngine(
            listDao: db.lists, itemDao: db.items, remote: remote, syncPoints: syncPoints, ownership: ownership,
            currentUserId: { "user-1" }, safeCall: SafeCall(reporter: SilentAppErrorReporter()))
    }

    // MARK: - Helpers

    private func seedList(
        _ id: String,
        accountId: String? = nil,
        shareCode: String? = nil,
        onServer: Bool = false,
        pendingSync: Bool = false
    ) async throws {
        try await listDao.insertList(ShoppingListRecord(
            id: id, name: "List \(id)", createdAt: 1, updatedAt: 2, isLocked: false,
            shareCode: shareCode, deletedAt: nil, pendingSync: pendingSync, accountId: accountId, onServer: onServer))
    }

    private func seedItem(_ id: String, listId: String, deletedAt: Int64? = nil) async throws {
        try await itemDao.insertItem(ShoppingItemRecord(
            id: id, listId: listId, name: "Milk", quantity: "1", isPickedUp: false, categoryId: nil,
            shop: nil, note: nil, createdAt: 1, updatedAt: 2, deletedAt: deletedAt, pendingSync: false))
    }

    private func listRow(_ id: String, updatedAt: String = "2026-08-01T10:00:00Z", name: String = "Server name")
        -> ListRow {
        ListRow(id: id, name: name, createdBy: "user-1", updatedAt: updatedAt, deletedAt: nil)
    }

    private func listRaw(_ id: String) async throws -> ShoppingListRecord? {
        try await listDao.listRaw(id: id)
    }

    private func itemRaw(_ id: String) async throws -> ShoppingItemRecord? {
        try await itemDao.itemRaw(id: id)
    }

    private func claimedCount(_ result: Result<Int, AppError>, file: StaticString = #filePath, line: UInt = #line) -> Int? {
        switch result {
        case .success(let count):
            return count
        case .failure(let error):
            XCTFail("expected success, got \(error)", file: file, line: line)
            return nil
        }
    }

    private func assertSuccess(_ result: Result<Void, AppError>, file: StaticString = #filePath, line: UInt = #line) {
        if case .failure(let error) = result { XCTFail("expected success, got \(error)", file: file, line: line) }
    }

    private func assertFailure(_ result: Result<Void, AppError>, file: StaticString = #filePath, line: UInt = #line) {
        if case .success = result { XCTFail("expected an error", file: file, line: line) }
    }

    // MARK: - claimDeviceLists

    func testGuestListsMoveIntoTheAccountAndAreQueuedWithTheirLiveItems() async throws {
        try await seedList("guest")
        try await seedItem("live", listId: "guest")
        try await seedItem("gone", listId: "guest", deletedAt: 5)

        let claimed = try await engine.claimDeviceLists(userId: "user-1")

        XCTAssertEqual(claimedCount(claimed), 1)
        let stored = try await listRaw("guest")
        let row = try XCTUnwrap(stored)
        XCTAssertEqual(row.accountId, "user-1")
        XCTAssertTrue(row.pendingSync, "the list has to be uploaded")
        let live = try await itemRaw("live")
        XCTAssertTrue(try XCTUnwrap(live).pendingSync)
        let gone = try await itemRaw("gone")
        XCTAssertFalse(try XCTUnwrap(gone).pendingSync, "a deleted item stays deleted, unsent")
    }

    func testAnotherAccountsListsAndTheirSyncPointsAreRemoved() async throws {
        try await seedList("theirs", accountId: "user-2", onServer: true)
        try await seedItem("their-item", listId: "theirs")
        syncPoints.set(listId: "theirs", iso: "2026-08-01T10:00:00Z")
        try await seedList("mine", accountId: "user-1", onServer: true)
        syncPoints.set(listId: "mine", iso: "2026-08-01T10:00:00Z")

        _ = try await engine.claimDeviceLists(userId: "user-1")

        let theirs = try await listRaw("theirs")
        XCTAssertNil(theirs)
        let theirItem = try await itemRaw("their-item")
        XCTAssertNil(theirItem, "CASCADE took the items")
        XCTAssertNil(syncPoints.get(listId: "theirs"))
        let mine = try await listRaw("mine")
        XCTAssertNotNil(mine)
        XCTAssertEqual(syncPoints.get(listId: "mine"), "2026-08-01T10:00:00Z")
    }

    // An already-signed-in user opening the update in a store with no signal
    // must still see their shared lists: the claim is local, no server needed.
    func testTheFirstClaimAfterTheUpdateAlsoClaimsSharedReplicasOffline() async throws {
        try await seedList("shared", shareCode: "ABC123", onServer: true)
        remote.failFetches = true
        remote.failUpserts = true

        let claimed = try await engine.claimDeviceLists(userId: "user-1")

        XCTAssertEqual(claimedCount(claimed), 0, "shared lists aren't news to the user")
        let stored = try await listRaw("shared")
        let row = try XCTUnwrap(stored)
        XCTAssertEqual(row.accountId, "user-1")
        XCTAssertFalse(row.pendingSync, "already on the server: nothing to upload")
        XCTAssertTrue(ownership.isAccountListsMigrated())
    }

    func testLaterClaimsLeaveOrphanedSharedReplicasAlone() async throws {
        ownership.markAccountListsMigrated()
        try await seedList("orphan", shareCode: "ABC123", onServer: true)

        _ = try await engine.claimDeviceLists(userId: "user-1")

        let orphan = try await listRaw("orphan")
        XCTAssertNil(try XCTUnwrap(orphan).accountId, "only discovery may claim it")
    }

    func testClaimingAddsToThePendingAdoptionNotice() async throws {
        ownership.setAdoptionNotice(2)
        try await seedList("a")
        try await seedList("b")
        try await seedList("c")

        _ = try await engine.claimDeviceLists(userId: "user-1")
        XCTAssertEqual(ownership.adoptionNotice, 5)

        _ = try await engine.claimDeviceLists(userId: "user-1") // nothing left to claim
        XCTAssertEqual(ownership.adoptionNotice, 5)
    }

    func testClaimingTwiceClaimsNothingTheSecondTime() async throws {
        try await seedList("guest")

        _ = try await engine.claimDeviceLists(userId: "user-1")
        let second = try await engine.claimDeviceLists(userId: "user-1")

        XCTAssertEqual(claimedCount(second), 0)
    }

    // MARK: - onAuthState: what a sign-in state change means for local lists

    func testALiveSessionClaimsAndAsksForASync() async throws {
        try await seedList("guest")

        let kick = await engine.onAuthState(.authenticated(userId: "user-1"))

        XCTAssertTrue(kick)
        let guest = try await listRaw("guest")
        XCTAssertEqual(guest?.accountId, "user-1")
    }

    // A dead token still knows whose lists these are: claim them so they stay
    // on screen, but there is nothing to sync with.
    func testAnExpiredSessionClaimsButDoesNotSync() async throws {
        try await seedList("guest")

        let kick = await engine.onAuthState(.sessionExpired(userId: "user-1"))

        XCTAssertFalse(kick)
        let guest = try await listRaw("guest")
        XCTAssertEqual(guest?.accountId, "user-1")
    }

    func testASignedOutFirstLaunchMarksTheMigrationDoneAndClaimsNothing() async throws {
        try await seedList("guest")

        let kick = await engine.onAuthState(.unauthenticated)

        XCTAssertFalse(kick)
        XCTAssertTrue(ownership.isAccountListsMigrated())
        let guest = try await listRaw("guest")
        XCTAssertNotNil(guest)
        XCTAssertNil(guest?.accountId)
    }

    func testLoadingDoesNothing() async throws {
        try await seedList("guest")

        let kick = await engine.onAuthState(.loading)

        XCTAssertFalse(kick)
        XCTAssertFalse(ownership.isAccountListsMigrated())
        let guest = try await listRaw("guest")
        XCTAssertNotNil(guest)
        XCTAssertNil(guest?.accountId)
    }

    // MARK: - releaseUnverifiedClaims

    // These two moved here unchanged from SyncEngineAccountCatchUpTests, where
    // they were ported before iOS had claimDeviceLists.
    //
    // Android SyncEngineClaimTest "first-run claims the server doesn't vouch for
    // are released after discovery". The claims are seeded directly: owned by
    // this account and listed as unverified.
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

    // The same two cases end to end through claimDeviceLists, as Android
    // runs them: the first claim records the ownerless replicas it took.
    func testAFirstClaimsUnverifiedReplicasAreReleasedByTheFirstDiscovery() async throws {
        try await seedList("mine", shareCode: "AAA111", onServer: true)
        try await seedList("stray", shareCode: "BBB222", onServer: true, pendingSync: true)
        _ = try await engine.claimDeviceLists(userId: "user-1")
        let claimedStray = try await listRaw("stray")
        XCTAssertEqual(claimedStray?.accountId, "user-1")
        remote.listRows = [listRow("mine", name: "List mine")]

        assertSuccess(try await engine.catchUpAccount())

        let mine = try await listRaw("mine")
        XCTAssertEqual(mine?.accountId, "user-1")
        let stray = try await listRaw("stray")
        XCTAssertNil(stray?.accountId, "not this account's: back to ownerless")
        XCTAssertTrue(ownership.unverifiedListIds().isEmpty)

        _ = try await engine.push()
        XCTAssertFalse(remote.upsertedLists.contains { $0.id == "stray" }, "a released stray is never pushed")
    }

    func testAFirstClaimsReplicasStayClaimedWhileTheServerDoesNotAnswer() async throws {
        try await seedList("stray", shareCode: "BBB222", onServer: true)
        _ = try await engine.claimDeviceLists(userId: "user-1")
        remote.failFetches = true

        assertFailure(try await engine.catchUpAccount())

        let stray = try await listRaw("stray")
        XCTAssertEqual(stray?.accountId, "user-1")
        XCTAssertEqual(ownership.unverifiedListIds(), ["stray"])
    }
}
