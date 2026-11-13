import GRDB
import XCTest
@testable import BabeGetThis

/// Port of Android's DeleteListIfEmptyTest plus the deleteListIfEmpty cases of
/// ShoppingListRepositoryTest and ShoppingListRepositorySharedTest. Real in-memory
/// database, and (for lists on the server) a real SyncEngine over the fake remote:
/// what matters is what lands in the database as a result.
final class DeleteListIfEmptyTests: XCTestCase {
    private var db: AppDatabase!
    private var kicker: CountingSyncKicker!
    private var remote: FakeSharedListRemote!
    private var kicks: Int { kicker.kicks }
    private var repository: ShoppingListRepository!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        kicker = CountingSyncKicker()
        remote = FakeSharedListRemote()
        // Everything outside the account sections runs as a guest.
        repository = repositoryAs(authStateFor(nil))
    }

    private func repositoryAs(_ auth: AuthStateManager) -> ShoppingListRepository {
        let safeCall = SafeCall(reporter: SilentAppErrorReporter())
        let engine = SyncEngine(
            listDao: db.lists, itemDao: db.items, remote: remote, syncPoints: FakeSyncPointStore(),
            ownership: FakeListOwnershipStore(), currentUserId: { auth.liveSessionUserId }, safeCall: safeCall)
        return ShoppingListRepository(
            listDao: db.lists,
            itemDao: db.items,
            categoryDao: db.categories,
            authStateManager: auth,
            syncKicker: kicker,
            safeCall: safeCall,
            catchUp: { try await engine.catchUp(listId: $0) })
    }

    /// Android ShoppingListRepositorySharedTest's repository: signed in as u1, with no
    /// sync engine, since the lists it auto-deletes have never been on the server.
    private var sharedTestRepository: ShoppingListRepository {
        ShoppingListRepository(
            listDao: db.lists,
            itemDao: db.items,
            categoryDao: db.categories,
            authStateManager: authStateFor("u1"),
            syncKicker: kicker,
            safeCall: SafeCall(reporter: SilentAppErrorReporter()))
    }

    private func data<T>(_ result: Result<T, AppError>, line: UInt = #line) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("expected success, got \(error)", line: line)
            throw error
        }
    }

    private func storedList(_ id: String, line: UInt = #line) async throws -> ShoppingListRecord {
        let raw = try await db.lists.listRaw(id: id)
        return try XCTUnwrap(raw, "no row \(id)", line: line)
    }

    // MARK: - DeleteListIfEmptyTest: the row count → Bool mapping

    func testReturnsTrueWhenTheEmptyListWasDeleted() async throws {
        try await db.lists.insertList(TestData.listEntity(id: "list-1"))

        let result = try await repository.deleteListIfEmpty(listId: "list-1")

        XCTAssertEqual(true, try data(result))
        let row = try await db.lists.listRaw(id: "list-1")
        XCTAssertNil(row)
    }

    func testReturnsFalseWhenTheListHadItemsAndWasKept() async throws {
        try await db.lists.insertList(TestData.listEntity(id: "list-1"))
        try await db.items.insertItem(TestData.itemEntity(listId: "list-1"))

        let result = try await repository.deleteListIfEmpty(listId: "list-1")

        XCTAssertEqual(false, try data(result))
        let row = try await db.lists.listRaw(id: "list-1")
        XCTAssertNotNil(row)
    }

    // MARK: - ShoppingListRepositoryTest: guest lists

    func testDeleteListIfEmptyReportsTrueWhenItRemovedTheList() async throws {
        let id = try data(await repository.createList(name: "Groceries"))

        let deleted = try data(await repository.deleteListIfEmpty(listId: id))
        XCTAssertEqual(true, deleted)
    }

    func testDeleteListIfEmptyReportsFalseWhenTheListHasItems() async throws {
        let id = try data(await repository.createList(name: "Groceries"))
        try await db.items.insertItem(TestData.itemEntity(listId: id))

        let deleted = try data(await repository.deleteListIfEmpty(listId: id))
        XCTAssertEqual(false, deleted)
    }

    func testDeleteListIfEmptyReportsFalseForAListThatDoesNotExist() async throws {
        let deleted = try data(await repository.deleteListIfEmpty(listId: "missing"))
        XCTAssertEqual(false, deleted)
    }

    // MARK: - ShoppingListRepositoryTest: account lists (Android docs/technical-decisions/008)
    //
    // "Empty on this phone" is only half the story for a list the account's other
    // phones can see: the deletion would reach them with no undo.

    private func seedOnServer(_ id: String, accountId: String = "u1", shareCode: String? = nil) async throws {
        try await db.lists.insertList(TestData.listEntity(id: id).with {
            $0.accountId = accountId
            $0.shareCode = shareCode
            $0.onServer = true
        })
    }

    func testASharedListIsNeverAutoDeleted() async throws {
        try await seedOnServer("shared", shareCode: "ABC234")

        let deleted = try data(await repositoryAs(authStateFor("u1")).deleteListIfEmpty(listId: "shared"))
        XCTAssertEqual(false, deleted)
        let row = try await storedList("shared")
        XCTAssertNil(row.deletedAt)
    }

    func testAnEmptyAccountListThatNeverReachedTheServerIsTombstonedWithoutAsking() async throws {
        let repo = repositoryAs(authStateFor("u1"))
        let id = try data(await repo.createList(name: "Groceries"))
        kicker.kicks = 0

        let deleted = try data(await repo.deleteListIfEmpty(listId: id))
        XCTAssertEqual(true, deleted)

        let row = try await storedList(id)
        XCTAssertNotNil(row.deletedAt, "a tombstone, which the push drops rather than uploads")
        XCTAssertTrue(remote.fetchedListIds.isEmpty, "nothing to ask the server about")
        XCTAssertEqual(1, kicks)
    }

    func testAnEmptyAccountListOnTheServerIsTombstonedOnceTheServerAgreesItIsEmpty() async throws {
        try await seedOnServer("solo")

        let deleted = try data(await repositoryAs(authStateFor("u1")).deleteListIfEmpty(listId: "solo"))
        XCTAssertEqual(true, deleted)

        XCTAssertEqual(["solo"], remote.fetchedListIds)
        let row = try await storedList("solo")
        XCTAssertNotNil(row.deletedAt)
        XCTAssertEqual(1, kicks)
    }

    func testAnEmptyLookingAccountListIsKeptWhenTheServerHasItemsForIt() async throws {
        try await seedOnServer("solo")
        remote.itemRows = [
            ItemRow(id: "x", listId: "solo", name: "Milk", quantity: "1", updatedAt: "2026-08-01T10:00:00Z"),
        ]

        let deleted = try data(await repositoryAs(authStateFor("u1")).deleteListIfEmpty(listId: "solo"))
        XCTAssertEqual(false, deleted)

        let row = try await storedList("solo")
        XCTAssertNil(row.deletedAt)
        let landed = try await db.items.itemRaw(id: "x")
        XCTAssertNotNil(landed, "the other phone's item landed")
        XCTAssertEqual(0, kicks)
    }

    func testAnEmptyAccountListIsKeptWhenTheServerCannotBeReached() async throws {
        try await seedOnServer("solo")
        remote.failFetches = true

        let deleted = try data(await repositoryAs(authStateFor("u1")).deleteListIfEmpty(listId: "solo"))
        XCTAssertEqual(false, deleted)

        let row = try await storedList("solo")
        XCTAssertNil(row.deletedAt)
        XCTAssertEqual(0, kicks)
    }

    func testAnEmptyAccountListIsKeptAfterALostSession() async throws {
        try await seedOnServer("solo")

        let deleted = try data(await repositoryAs(authStateFor("u1", expired: true)).deleteListIfEmpty(listId: "solo"))
        XCTAssertEqual(false, deleted)

        XCTAssertTrue(remote.fetchedListIds.isEmpty)
        let row = try await storedList("solo")
        XCTAssertNil(row.deletedAt)
    }

    func testATombstonedAccountListIsNotDeletedTwice() async throws {
        try await seedOnServer("solo")
        try await db.lists.softDeleteList(id: "solo", now: 5)

        let deleted = try data(await repositoryAs(authStateFor("u1")).deleteListIfEmpty(listId: "solo"))
        XCTAssertEqual(false, deleted)
    }

    // MARK: - ShoppingListRepositorySharedTest

    /// Android `sharedList()`: a shared account list that hasn't been on the server.
    private func sharedList(shareCode: String? = "ABC234") -> ShoppingListRecord {
        TestData.listEntity(id: "list-1", name: "Groceries", createdAt: 1, updatedAt: 2).with {
            $0.shareCode = shareCode
            $0.accountId = "u1"
        }
    }

    func testAnEmptySharedListIsNeverAutoDeleted() async throws {
        try await db.lists.insertList(sharedList())

        let deleted = try data(await sharedTestRepository.deleteListIfEmpty(listId: "list-1"))

        XCTAssertFalse(deleted)
        let row = try await db.lists.listRaw(id: "list-1")
        XCTAssertNotNil(row)
    }

    func testAnEmptyUnsharedAccountListIsTombstonedNotDeleted() async throws {
        try await db.lists.insertList(sharedList(shareCode: nil))

        let deleted = try data(await sharedTestRepository.deleteListIfEmpty(listId: "list-1"))

        XCTAssertTrue(deleted)
        let row = try await storedList("list-1")
        XCTAssertNotNil(row.deletedAt, "the deletion has to reach the account's other phones")
        XCTAssertTrue(row.pendingSync)
        XCTAssertEqual(1, kicks)
    }

    func testAnUnsharedAccountListWithItemsIsKept() async throws {
        try await db.lists.insertList(sharedList(shareCode: nil))
        try await db.items.insertItem(TestData.itemEntity(id: "i1", listId: "list-1"))

        let deleted = try data(await sharedTestRepository.deleteListIfEmpty(listId: "list-1"))

        XCTAssertFalse(deleted)
        let row = try await storedList("list-1")
        XCTAssertNil(row.deletedAt)
        XCTAssertEqual(0, kicks)
    }
}
