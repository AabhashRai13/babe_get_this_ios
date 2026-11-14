import Foundation
import XCTest
@testable import BabeGetThis

/// What the sign-out step saw, written from inside `andThen`.
final class SignOutObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var _listsLeft: Int?

    var listsLeft: Int? {
        get { lock.withLock { _listsLeft } }
        set { lock.withLock { _listsLeft = newValue } }
    }
}

// Port of the eviction cases of Android `SyncEngineTest` (ACCT-06, SYNC-20),
// minus the purchase-history one (Got This).
//
// Explicit sign-out and account deletion take every account list off the
// phone (docs/technical-decisions/008); guest lists are the device's.
final class SyncEngineEvictionTests: XCTestCase {
    private var db: AppDatabase!
    private var remote: FakeSharedListRemote!
    private var syncPoints: FakeSyncPointStore!
    private var ownership: FakeListOwnershipStore!
    private var userId: SyncTestUserId!
    private var engine: SyncEngine!

    private var listDao: ShoppingListDao { db.lists }
    private var itemDao: ShoppingItemDao { db.items }

    private let t10 = "2026-08-01T10:00:00Z"

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
        pendingSync: Bool = false,
        accountId: String? = "user-1",
        onServer: Bool = true
    ) -> ShoppingListRecord {
        ShoppingListRecord(
            id: id, name: "Groceries", createdAt: 500, updatedAt: 1_000, isLocked: false,
            shareCode: shareCode, deletedAt: nil, pendingSync: pendingSync,
            accountId: accountId, onServer: onServer)
    }

    private func itemEntity(id: String = "item-1", listId: String = "list-1", pendingSync: Bool = false)
        -> ShoppingItemRecord {
        ShoppingItemRecord(
            id: id, listId: listId, name: "Milk", quantity: "1", isPickedUp: false, categoryId: nil,
            shop: nil, note: nil, createdAt: 500, updatedAt: 1_000, deletedAt: nil, pendingSync: pendingSync)
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

    // MARK: - Cases

    func testEvictionRemovesAccountListsAndOrphanedReplicasButKeepsGuestLists() async throws {
        try await listDao.insertList(listEntity(id: "shared-1"))
        try await itemDao.insertItem(itemEntity(id: "i1", listId: "shared-1", pendingSync: true))
        try await listDao.insertList(listEntity(id: "solo-1", shareCode: nil))
        try await listDao.insertList(listEntity(id: "orphan-1", accountId: nil))
        try await listDao.insertList(listEntity(id: "guest-1", shareCode: nil, accountId: nil, onServer: false))
        syncPoints.set(listId: "shared-1", iso: t10)

        let result = try await engine.evictAccountLists()

        assertSuccess(result)
        XCTAssertEqual(remote.upsertedItems.map(\.id), ["i1"], "queued edit pushed before eviction")
        let shared = try await listRaw("shared-1")
        XCTAssertNil(shared)
        let item = try await itemRaw("i1")
        XCTAssertNil(item, "its items gone via CASCADE")
        let solo = try await listRaw("solo-1")
        XCTAssertNil(solo)
        let orphan = try await listRaw("orphan-1")
        XCTAssertNil(orphan)
        let guest = try await listRaw("guest-1")
        XCTAssertNotNil(guest, "guest list untouched")
        XCTAssertTrue(syncPoints.points.isEmpty, "sync points wiped")
    }

    func testEvictionStillHappensWhenTheFinalPushCannotRun() async throws {
        userId.value = nil // signed-out-ish: push no-ops, eviction must proceed
        try await listDao.insertList(listEntity(id: "shared-1"))

        _ = try await engine.evictAccountLists()

        let shared = try await listRaw("shared-1")
        XCTAssertNil(shared)
    }

    func testEvictionStillHappensWhenTheFinalPushFails() async throws {
        try await listDao.insertList(listEntity(id: "shared-1", pendingSync: true))
        remote.failUpserts = true

        let result = try await engine.evictAccountLists()

        assertSuccess(result)
        let shared = try await listRaw("shared-1")
        XCTAssertNil(shared)
    }

    // The sign-out runs inside the eviction: a sync kick waiting on the gate
    // would otherwise run between the two, with the session still live, and
    // land the lists again.
    func testEvictionRunsTheSignOutAfterTheListsAreGoneInTheSameStep() async throws {
        try await listDao.insertList(listEntity(id: "shared-1"))
        let seen = SignOutObservation()
        let listDao = listDao

        _ = try await engine.evictAccountLists {
            seen.listsLeft = try await listDao.listRaw(id: "shared-1") == nil ? 0 : 1
        }

        XCTAssertEqual(seen.listsLeft, 0)
    }

    // Eviction while discovery is mid-request: without the gate the catch-up
    // would land the account's lists again after they had been evicted.
    func testAnEvictionWaitsForACatchUpInFlightInsteadOfRacingIt() async throws {
        remote.listRows = [ListRow(id: "l1", name: "Groceries", shareCode: "ABC123", createdBy: "user-1",
                                   updatedAt: t10, deletedAt: nil)]
        let hook = ParkingHook()
        remote.onFetchAllLists = { await hook.park() }
        let engine = engine!

        let catchUp = Task { try await engine.catchUpAccount() }
        try await hook.waitForEntries(1)
        let evict = Task { try await engine.evictAccountLists() }
        try await Task.sleep(for: .milliseconds(100))
        hook.release()
        assertSuccess(try await catchUp.value)
        assertSuccess(try await evict.value)

        let list = try await listRaw("l1")
        XCTAssertNil(list)
    }
}
