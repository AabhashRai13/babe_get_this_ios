import XCTest
@testable import BabeGetThis

final class ShoppingItemDaoTests: XCTestCase {
    private var db: AppDatabase!
    private var listDao: ShoppingListDao { db.lists }
    private var itemDao: ShoppingItemDao { db.items }

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
    }

    func testItemsAreOrderedByShopThenCategoryThenNameWithNullsLast() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        try await itemDao.saveItems([
            TestData.itemEntity(id: "no-shop", listId: "l1", name: "A"),
            TestData.itemEntity(id: "costco-dairy", listId: "l1", name: "Milk", categoryId: "cat-dairy-eggs", shop: "Costco"),
            TestData.itemEntity(id: "costco-none", listId: "l1", name: "Batteries", shop: "Costco"),
            TestData.itemEntity(id: "aldi-b", listId: "l1", name: "Bread", categoryId: "cat-bakery-bread", shop: "Aldi"),
            TestData.itemEntity(id: "aldi-a", listId: "l1", name: "Apples", categoryId: "cat-bakery-bread", shop: "Aldi"),
        ])

        let ids = try await itemDao.itemsByListId("l1").map(\.id)

        XCTAssertEqual(ids, ["aldi-a", "aldi-b", "costco-dairy", "costco-none", "no-shop"])
    }

    func testItemQueriesSkipTombstonesAndOtherLists() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        try await listDao.insertList(TestData.listEntity(id: "l2"))
        try await itemDao.insertItem(TestData.itemEntity(id: "live", listId: "l1"))
        try await itemDao.insertItem(TestData.itemEntity(id: "other", listId: "l2"))
        try await itemDao.insertItem(TestData.itemEntity(id: "gone", listId: "l1"))
        try await itemDao.softDeleteItem(id: "gone", now: 7)

        let ordered = try await itemDao.itemsByListId("l1").map(\.id)
        let once = try await itemDao.itemsByListIdOnce("l1").map(\.id)
        let raw = try await itemDao.itemRaw(id: "gone")
        let active = try await itemDao.countActiveItems()

        XCTAssertEqual(ordered, ["live"])
        XCTAssertEqual(once, ["live"])
        XCTAssertEqual(raw?.deletedAt, 7)
        XCTAssertEqual(raw?.updatedAt, 7)
        XCTAssertEqual(raw?.pendingSync, true)
        XCTAssertEqual(active, 2)
    }

    func testSetPickedUpTicksAndMarksPending() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i1", listId: "l1"))

        try await itemDao.setPickedUp(itemId: "i1", isPickedUp: true, updatedAt: 99, pendingSync: true)

        let item = try await itemDao.itemRaw(id: "i1")
        XCTAssertEqual(item?.isPickedUp, true)
        XCTAssertEqual(item?.updatedAt, 99)
        XCTAssertEqual(item?.pendingSync, true)
    }

    func testSaveItemUpdatesAnExistingItemInPlace() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        let item = TestData.itemEntity(id: "i1", listId: "l1", name: "Milk")
        try await itemDao.insertItem(item)

        try await itemDao.saveItem(item.with { $0.name = "Oat milk"; $0.note = "barista" })
        try await itemDao.updateItem(item.with { $0.name = "Oat milk"; $0.quantity = "2" })

        let items = try await itemDao.itemsByListIdOnce("l1")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Oat milk")
        XCTAssertEqual(items.first?.quantity, "2")
    }

    func testDeleteItemRemovesOnlyThatItem() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i1", listId: "l1"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i2", listId: "l1"))

        try await itemDao.deleteItem(id: "i1")

        let ids = try await itemDao.itemsByListIdOnce("l1").map(\.id)
        XCTAssertEqual(ids, ["i2"])
    }

    func testPendingItemsAreScopedToTheAccountAndIncludeTombstones() async throws {
        try await listDao.insertList(TestData.listEntity(id: "mine").with { $0.accountId = "u1" })
        try await listDao.insertList(TestData.listEntity(id: "theirs").with { $0.accountId = "u2" })
        try await itemDao.insertItem(TestData.itemEntity(id: "a", listId: "mine").with { $0.pendingSync = true })
        try await itemDao.insertItem(TestData.itemEntity(id: "b", listId: "mine").with {
            $0.pendingSync = true
            $0.deletedAt = 3
        })
        try await itemDao.insertItem(TestData.itemEntity(id: "c", listId: "mine"))
        try await itemDao.insertItem(TestData.itemEntity(id: "d", listId: "theirs").with { $0.pendingSync = true })

        let pending = try await itemDao.pendingSyncItemsForAccount("u1").map(\.id)
        let count = try await itemDao.countPendingSyncItemsForAccount("u1")
        let all = try await itemDao.countPendingSync()

        XCTAssertEqual(Set(pending), ["a", "b"])
        XCTAssertEqual(count, 2)
        XCTAssertEqual(all, 3)
    }

    func testMarkItemSyncedOnlyClearsTheFlagForTheSameSnapshot() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i1", listId: "l1", updatedAt: 10).with { $0.pendingSync = true })

        try await itemDao.markItemSynced(id: "i1", updatedAt: 9)
        let before = try await itemDao.itemRaw(id: "i1")
        try await itemDao.markItemSynced(id: "i1", updatedAt: 10)
        let after = try await itemDao.itemRaw(id: "i1")

        XCTAssertEqual(before?.pendingSync, true)
        XCTAssertEqual(after?.pendingSync, false)
    }
}
