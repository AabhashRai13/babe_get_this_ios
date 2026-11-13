import XCTest
@testable import BabeGetThis

/// Port of Android's ShoppingItemRepositorySharedTest minus the Got This cases (tick time,
/// TickResult, purchase records) and reminder assertions, which are out of iOS v1.
/// Item writes on account lists: dirty flags, soft delete, undo revival, push kicks.
final class ShoppingItemRepositoryTests: XCTestCase {
    private var db: AppDatabase!
    private var kicker: CountingSyncKicker!
    private var repository: ShoppingItemRepository!
    private var kicks: Int {
        get { kicker.kicks }
        set { kicker.kicks = newValue }
    }

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        kicker = CountingSyncKicker()
        repository = ShoppingItemRepository(
            itemDao: db.items,
            categoryDao: db.categories,
            listDao: db.lists,
            syncKicker: kicker,
            safeCall: SafeCall(reporter: SilentAppErrorReporter()))
    }

    /// Defaults to a shared list of account u1. Sync is decided by the owner, not the
    /// share code (Android docs/technical-decisions/008).
    private func seedList(shareCode: String? = "ABC234", accountId: String? = "u1") async throws {
        try await db.lists.insertList(TestData.listEntity(id: "list-1").with {
            $0.shareCode = shareCode
            $0.accountId = accountId
        })
    }

    private func data<T>(_ result: Result<T, AppError>, line: UInt = #line) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("expected success, got \(error)", line: line)
            throw error
        }
    }

    @discardableResult
    private func addMilk() async throws -> String {
        try data(try await repository.addItem(listId: "list-1", name: "Milk", quantity: "1"))
    }

    private func pending() async throws -> [ShoppingItemRecord] {
        try await db.items.pendingSyncItemsForAccount("u1")
    }

    private func row(_ id: String, line: UInt = #line) async throws -> ShoppingItemRecord {
        let stored = try await db.items.itemRaw(id: id)
        return try XCTUnwrap(stored, "no row \(id)", line: line)
    }

    private func clearDirty() async throws {
        for item in try await pending() {
            try await db.items.markItemSynced(id: item.id, updatedAt: item.updatedAt)
        }
    }

    private func domainItem() async throws -> StoredShoppingItem {
        let items = try await firstValue(repository.itemsByListId("list-1"))
        XCTAssertEqual(items.count, 1)
        return try XCTUnwrap(items.first)
    }

    func testAddingToASharedListMarksTheItemDirtyAndKicks() async throws {
        try await seedList()

        try await addMilk()

        let rows = try await pending()
        XCTAssertEqual(rows.map(\.name), ["Milk"])
        XCTAssertEqual(kicks, 1)
    }

    func testAddingToAnUnsharedAccountListMarksTheItemDirtyAndKicks() async throws {
        try await seedList(shareCode: nil)

        try await addMilk()

        let rows = try await pending()
        XCTAssertEqual(rows.map(\.name), ["Milk"])
        XCTAssertEqual(kicks, 1)
    }

    func testAddingToALocalOnlyListStaysCleanAndQuiet() async throws {
        try await seedList(shareCode: nil, accountId: nil)

        try await addMilk()

        let pendingRows = try await pending()
        XCTAssertTrue(pendingRows.isEmpty)
        XCTAssertEqual(kicks, 0)
    }

    func testAddingABlankNameIsAValidationErrorAndStoresNothing() async throws {
        try await seedList()

        let result = try await repository.addItem(listId: "list-1", name: "   ", quantity: "1")

        guard case .failure(.validation) = result else {
            return XCTFail("expected validation error, got \(result)")
        }
        let stored = try await db.items.itemsByListIdOnce("list-1")
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(kicks, 0)
    }

    func testAddingTrimsTheName() async throws {
        try await seedList(shareCode: nil, accountId: nil)

        let id = try data(try await repository.addItem(listId: "list-1", name: "  Milk \n", quantity: "1"))

        let stored = try await row(id)
        XCTAssertEqual(stored.name, "Milk")
    }

    func testEditingASharedItemMarksItDirtyAndKicks() async throws {
        try await seedList()
        try await addMilk()
        kicks = 0
        try await clearDirty()

        let item = try await domainItem()
        _ = try await repository.updateItem(item.with { $0.name = "Oat milk" })

        let rows = try await pending()
        XCTAssertEqual(rows.map(\.name), ["Oat milk"])
        XCTAssertEqual(kicks, 1)
    }

    func testTickingASharedItemMarksItDirtyAndKicks() async throws {
        try await seedList()
        let id = try await addMilk()
        kicks = 0
        try await clearDirty()

        _ = try await repository.togglePickedUp(itemId: id, isPickedUp: true)

        let stored = try await row(id)
        XCTAssertTrue(stored.isPickedUp)
        XCTAssertTrue(stored.pendingSync)
        XCTAssertEqual(kicks, 1)
    }

    func testUntickingAPickedUpItemClearsTheFlag() async throws {
        try await seedList()
        let id = try await addMilk()
        _ = try await repository.togglePickedUp(itemId: id, isPickedUp: true)

        _ = try await repository.togglePickedUp(itemId: id, isPickedUp: false)

        let stored = try await row(id)
        XCTAssertFalse(stored.isPickedUp)
        XCTAssertTrue(stored.pendingSync)
    }

    func testTickingALocalOnlyItemStaysCleanAndQuiet() async throws {
        try await seedList(shareCode: nil, accountId: nil)
        let id = try await addMilk()

        _ = try await repository.togglePickedUp(itemId: id, isPickedUp: true)

        let stored = try await row(id)
        XCTAssertTrue(stored.isPickedUp)
        XCTAssertFalse(stored.pendingSync)
        XCTAssertEqual(kicks, 0)
    }

    func testTickingAMissingItemIsAQuietNoOp() async throws {
        let result = try await repository.togglePickedUp(itemId: "ghost", isPickedUp: true)

        _ = try data(result)
        XCTAssertEqual(kicks, 0)
    }

    func testDeletingASharedItemTombstonesItAndKicks() async throws {
        try await seedList()
        let id = try await addMilk()
        kicks = 0

        _ = try await repository.deleteItem(itemId: id)

        let stored = try await row(id)
        XCTAssertNotNil(stored.deletedAt, "soft-deleted, row survives")
        XCTAssertTrue(stored.pendingSync)
        let visible = try await db.items.itemsByListIdOnce("list-1")
        XCTAssertTrue(visible.isEmpty, "hidden from the UI query")
        XCTAssertEqual(kicks, 1)
    }

    func testDeletingALocalOnlyItemStillHardDeletes() async throws {
        try await seedList(shareCode: nil, accountId: nil)
        let id = try await addMilk()

        _ = try await repository.deleteItem(itemId: id)

        let stored = try await db.items.itemRaw(id: id)
        XCTAssertNil(stored, "row actually gone")
        XCTAssertEqual(kicks, 0)
    }

    func testUndoingASharedItemDeleteRevivesTheTombstonedRow() async throws {
        try await seedList()
        let id = try await addMilk()
        let item = try await domainItem()
        _ = try await repository.deleteItem(itemId: id)
        kicks = 0

        _ = try await repository.restoreItem(item)

        let stored = try await row(id)
        XCTAssertNil(stored.deletedAt, "alive again")
        XCTAssertTrue(stored.pendingSync, "revival must sync to members")
        XCTAssertEqual(kicks, 1)
    }

    func testEditingATickedItemKeepsItTicked() async throws {
        try await seedList()
        let id = try await addMilk()
        _ = try await repository.togglePickedUp(itemId: id, isPickedUp: true)

        let item = try await domainItem()
        _ = try await repository.updateItem(item.with { $0.quantity = "2" })

        let stored = try await row(id)
        XCTAssertEqual(stored.quantity, "2")
        XCTAssertTrue(stored.isPickedUp)
    }

    func testItemsStreamResolvesCategoryNames() async throws {
        try await seedList(shareCode: nil, accountId: nil)
        try await db.categories.insertCategory(TestData.categoryEntity(id: "cat-1", name: "Dairy"))
        _ = try data(try await repository.addItem(
            listId: "list-1", name: "Milk", quantity: "1", categoryId: "cat-1"))

        let item = try await domainItem()

        XCTAssertEqual(item.categoryName, "Dairy")
    }
}

private extension StoredShoppingItem {
    func with(_ change: (inout Self) -> Void) -> Self {
        var copy = self
        change(&copy)
        return copy
    }
}
