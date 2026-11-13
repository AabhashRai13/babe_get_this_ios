import GRDB
import XCTest
@testable import BabeGetThis

/// Port of the delete / undo cases of Android's ShoppingListRepositoryTest and
/// ShoppingListRepositorySharedTest. Real in-memory database, not mocked DAOs.
final class ListDeleteUndoTests: XCTestCase {
    private var db: AppDatabase!
    private var kicker: CountingSyncKicker!
    private var kicks: Int { kicker.kicks }
    private var repository: ShoppingListRepository!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        kicker = CountingSyncKicker()
        repository = repositoryAs(authStateFor(nil))
    }

    private func repositoryAs(_ auth: AuthStateManager) -> ShoppingListRepository {
        ShoppingListRepository(
            listDao: db.lists,
            itemDao: db.items,
            categoryDao: db.categories,
            authStateManager: auth,
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

    /// A shared account list (Android `sharedList()`), already on the server.
    private func seedShared(shareCode: String? = "ABC234") async throws {
        try await db.lists.insertList(TestData.listEntity(id: "list-1", name: "Groceries").with {
            $0.accountId = "u1"
            $0.shareCode = shareCode
            $0.onServer = true
        })
    }

    private var signedIn: ShoppingListRepository { repositoryAs(authStateFor("u1")) }

    private let groceries = ShoppingList(id: "list-1", name: "Groceries", createdAt: 1, updatedAt: 2)

    // MARK: - ShoppingListRepositoryTest: delete / restore

    func testDeleteListAndCaptureItemsReturnsTheItemsItIsAboutToDestroy() async throws {
        let id = try data(await repository.createList(name: "Groceries"))
        try await db.items.insertItem(TestData.itemEntity(id: "i1", listId: id))
        try await db.items.insertItem(TestData.itemEntity(id: "i2", listId: id))

        let captured = try data(await repository.deleteListAndCaptureItems(listId: id))

        XCTAssertEqual(["i1", "i2"], Set(captured.map(\.id)))
        let lists = try await firstValue(repository.allLists())
        XCTAssertTrue(lists.isEmpty)
        let left = try await db.items.itemsByListIdOnce(id)
        XCTAssertTrue(left.isEmpty, "CASCADE should have removed them")
    }

    func testDeleteListAndCaptureItemsOnAnEmptyListReturnsNothing() async throws {
        let id = try data(await repository.createList(name: "Groceries"))

        let captured = try data(await repository.deleteListAndCaptureItems(listId: id))
        XCTAssertTrue(captured.isEmpty)
    }

    // The whole point of the undo cache: the list AND its items come back, so the
    // derived completion state recomputes correctly.
    func testRestoreListWithItemsBringsBackTheListAndItsItems() async throws {
        let id = try data(await repository.createList(name: "Groceries"))
        try await db.items.insertItem(TestData.itemEntity(id: "i1", listId: id, isPickedUp: true))
        try await db.items.insertItem(TestData.itemEntity(id: "i2", listId: id, isPickedUp: false))
        let original = try await firstValue(repository.allLists()).first!
        let captured = try data(await repository.deleteListAndCaptureItems(listId: id))

        _ = try data(await repository.restoreListWithItems(list: original, items: captured))

        let restored = try await firstValue(repository.allLists())
        XCTAssertEqual(1, restored.count)
        XCTAssertEqual(id, restored[0].id)
        XCTAssertEqual(2, restored[0].itemCount)
        XCTAssertEqual(1, restored[0].completedItemCount)
    }

    // The push drops a list deleted before it ever reached the server rather than
    // uploading its tombstone, so by the time Undo is tapped the row can be gone.
    // It comes back as the account's, queued, as a new list would.
    func testRestoringAListWhoseRowIsGoneGivesItBackToTheAccount() async throws {
        let repo = signedIn
        let id = try data(await repo.createList(name: "Groceries"))
        try await db.items.insertItem(TestData.itemEntity(id: "i1", listId: id))
        let original = try await firstValue(repo.allLists()).first!
        let captured = try data(await repo.deleteListAndCaptureItems(listId: id))
        try await db.lists.deleteNeverSentDeletedLists()
        let gone = try await db.lists.listRaw(id: id)
        XCTAssertNil(gone)
        kicker.kicks = 0

        _ = try data(await repo.restoreListWithItems(list: original, items: captured))

        let row = try await storedList(id)
        XCTAssertEqual("u1", row.accountId)
        XCTAssertTrue(row.pendingSync)
        let item = try await db.items.itemRaw(id: "i1")
        XCTAssertEqual(true, item?.pendingSync)
        XCTAssertEqual(1, kicks)
    }

    func testRestoreListWithItemsHandlesAListThatHadNoItems() async throws {
        let id = try data(await repository.createList(name: "Groceries"))
        let original = try await firstValue(repository.allLists()).first!
        _ = try data(await repository.deleteListAndCaptureItems(listId: id))

        _ = try data(await repository.restoreListWithItems(list: original, items: []))

        let lists = try await firstValue(repository.allLists())
        XCTAssertEqual(id, lists.first?.id)
    }

    // MARK: - ShoppingListRepositorySharedTest: delete / undo

    func testDeletingASharedListSoftDeletesAndKeepsTheItemRows() async throws {
        try await seedShared()
        try await db.items.insertItem(TestData.itemEntity(id: "i1", listId: "list-1"))

        let captured = try data(await repository.deleteListAndCaptureItems(listId: "list-1"))

        XCTAssertEqual(1, captured.count)
        let row = try await storedList("list-1")
        XCTAssertNotNil(row.deletedAt, "tombstoned, not gone")
        XCTAssertTrue(row.pendingSync)
        let item = try await db.items.itemRaw(id: "i1")
        XCTAssertNotNil(item, "item rows survive behind the tombstone")
        XCTAssertEqual(1, kicks)
    }

    func testDeletingALocalOnlyListStillHardDeletesWithCascade() async throws {
        try await db.lists.insertList(TestData.listEntity(id: "list-1"))
        try await db.items.insertItem(TestData.itemEntity(id: "i1", listId: "list-1"))

        _ = try data(await repository.deleteListAndCaptureItems(listId: "list-1"))

        let row = try await db.lists.listRaw(id: "list-1")
        XCTAssertNil(row)
        let item = try await db.items.itemRaw(id: "i1")
        XCTAssertNil(item, "CASCADE wiped it")
        XCTAssertEqual(0, kicks)
    }

    func testUndoingASharedDeleteClearsTheTombstoneAndKeepsTheShareCode() async throws {
        try await seedShared()
        try await db.items.insertItem(TestData.itemEntity(id: "i1", listId: "list-1"))
        let captured = try data(await repository.deleteListAndCaptureItems(listId: "list-1"))

        _ = try data(await repository.restoreListWithItems(list: groceries, items: captured))

        let row = try await storedList("list-1")
        XCTAssertNil(row.deletedAt, "alive again")
        XCTAssertEqual("ABC234", row.shareCode, "share survives the undo round-trip")
        XCTAssertTrue(row.pendingSync, "revival must sync to members")
        let item = try await db.items.itemRaw(id: "i1")
        XCTAssertNotNil(item, "undo must not cascade the items away")
        XCTAssertEqual(2, kicks, "delete + restore")
    }

    func testDeletingAnUnsharedAccountListTombstonesItAndUndoClearsTheTombstone() async throws {
        try await seedShared(shareCode: nil)
        try await db.items.insertItem(TestData.itemEntity(id: "i1", listId: "list-1"))
        try await db.items.insertItem(TestData.itemEntity(id: "i2", listId: "list-1"))
        let captured = try data(await repository.deleteListAndCaptureItems(listId: "list-1"))
        let tombstoned = try await storedList("list-1")
        XCTAssertNotNil(tombstoned.deletedAt, "tombstoned, not gone")

        _ = try data(await repository.restoreListWithItems(list: groceries, items: captured))

        let row = try await storedList("list-1")
        XCTAssertNil(row.deletedAt)
        XCTAssertEqual("u1", row.accountId, "still the account's list")
        XCTAssertTrue(row.pendingSync)
        let i1 = try await db.items.itemRaw(id: "i1")
        let i2 = try await db.items.itemRaw(id: "i2")
        XCTAssertNotNil(i1)
        XCTAssertNotNil(i2)
        XCTAssertEqual(2, kicks)
    }
}
