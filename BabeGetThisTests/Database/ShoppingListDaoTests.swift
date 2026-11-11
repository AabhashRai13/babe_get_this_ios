import XCTest
@testable import BabeGetThis

// Port of Android `ShoppingListDaoTest` (23 cases), against a real in-memory
// SQLite database: the behaviour worth testing IS the SQL — the join-and-aggregate,
// the CASCADE and the atomic check-and-delete.
final class ShoppingListDaoTests: XCTestCase {
    private var db: AppDatabase!
    private var listDao: ShoppingListDao { db.lists }
    private var itemDao: ShoppingItemDao { db.items }

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
    }

    private func catalogIds(_ accountId: String?) async throws -> [String] {
        try await listDao.listsWithItemCount(accountId: accountId).map(\.id)
    }

    // One query for both owners: nil is the guest's lists, an id the account's.
    // An ownerless shared replica is neither.
    func testListsWithItemCountShowsOneOwnersLists() async throws {
        try await listDao.insertList(TestData.listEntity(id: "guest"))
        try await listDao.insertList(TestData.listEntity(id: "mine").with { $0.accountId = "u1" })
        try await listDao.insertList(TestData.listEntity(id: "theirs").with { $0.accountId = "u2" })
        try await listDao.insertList(TestData.listEntity(id: "orphan").with { $0.shareCode = "ABC234" })

        let guest = try await catalogIds(nil)
        let mine = try await catalogIds("u1")
        XCTAssertEqual(guest, ["guest"])
        XCTAssertEqual(mine, ["mine"])
    }

    func testListsWithItemCountCountsItemsAndCompletions() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i1", listId: "l1", isPickedUp: true))
        try await itemDao.insertItem(TestData.itemEntity(id: "i2", listId: "l1", isPickedUp: true))
        try await itemDao.insertItem(TestData.itemEntity(id: "i3", listId: "l1", isPickedUp: false))

        let rows = try await listDao.listsWithItemCount(accountId: nil)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.itemCount, 3)
        XCTAssertEqual(rows.first?.completedItemCount, 2)
    }

    // The LEFT JOIN produces one all-null row for a list with no items, so both
    // aggregates must come back as 0.
    func testListWithNoItemsReportsZeroCounts() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))

        let rows = try await listDao.listsWithItemCount(accountId: nil)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.itemCount, 0)
        XCTAssertEqual(rows.first?.completedItemCount, 0)
    }

    func testListsAreOrderedNewestFirst() async throws {
        try await listDao.insertList(TestData.listEntity(id: "old", createdAt: TestData.t0))
        try await listDao.insertList(TestData.listEntity(id: "new", createdAt: TestData.t0 + TestData.day))

        let ids = try await catalogIds(nil)

        XCTAssertEqual(ids, ["new", "old"])
    }

    func testCountsAreScopedPerList() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        try await listDao.insertList(TestData.listEntity(id: "l2"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i1", listId: "l1"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i2", listId: "l2"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i3", listId: "l2"))

        let rows = try await listDao.listsWithItemCount(accountId: nil)
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

        XCTAssertEqual(byId["l1"]?.itemCount, 1)
        XCTAssertEqual(byId["l2"]?.itemCount, 2)
    }

    func testListByIdIsNilForAMissingId() async throws {
        let list = try await listDao.list(id: "nope")
        XCTAssertNil(list)
    }

    func testListByIdReturnsTheStoredRow() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1", name: "Hardware"))

        let list = try await listDao.list(id: "l1")

        XCTAssertEqual(list?.name, "Hardware")
    }

    func testSetLockedTogglesASingleList() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        try await listDao.insertList(TestData.listEntity(id: "l2"))

        try await listDao.setLocked(listId: "l1", locked: true)

        let l1 = try await listDao.list(id: "l1")
        let l2 = try await listDao.list(id: "l2")
        XCTAssertEqual(l1?.isLocked, true)
        XCTAssertEqual(l2?.isLocked, false)
    }

    func testUnlockAllClearsEveryLockedList() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1", isLocked: true))
        try await listDao.insertList(TestData.listEntity(id: "l2", isLocked: true))
        try await listDao.insertList(TestData.listEntity(id: "l3", isLocked: false))

        try await listDao.unlockAll()

        let rows = try await listDao.listsWithItemCount(accountId: nil)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { !$0.isLocked })
    }

    func testLockedCountCountsOnlyLockedLists() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1", isLocked: true))
        try await listDao.insertList(TestData.listEntity(id: "l2", isLocked: false))
        try await listDao.insertList(TestData.listEntity(id: "l3", isLocked: true))

        let count = try await listDao.lockedCount()

        XCTAssertEqual(count, 2)
    }

    func testLockedCountIsZeroWithNoLists() async throws {
        let count = try await listDao.lockedCount()
        XCTAssertEqual(count, 0)
    }

    // The undo-delete flow depends on this: deleting the list takes its items with it.
    func testDeletingAListCascadesToItsItems() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i1", listId: "l1"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i2", listId: "l1"))

        try await listDao.deleteList(id: "l1")

        let items = try await itemDao.itemsByListIdOnce("l1")
        XCTAssertTrue(items.isEmpty)
    }

    func testDeleteListIfEmptyRemovesAnEmptyListAndReportsOneRow() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))

        let deleted = try await listDao.deleteListIfEmpty(id: "l1")
        let list = try await listDao.list(id: "l1")

        XCTAssertEqual(deleted, 1)
        XCTAssertNil(list)
    }

    func testDeleteListIfEmptyKeepsAListThatHasItems() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i1", listId: "l1"))

        let deleted = try await listDao.deleteListIfEmpty(id: "l1")
        let list = try await listDao.list(id: "l1")

        XCTAssertEqual(deleted, 0)
        XCTAssertEqual(list?.id, "l1")
    }

    func testDeleteListIfEmptyReportsZeroForAListThatDoesNotExist() async throws {
        let deleted = try await listDao.deleteListIfEmpty(id: "nope")
        XCTAssertEqual(deleted, 0)
    }

    // Android's insertList REPLACEs; iOS never does. saveList UPDATEs the existing row.
    func testSaveListUpdatesOnConflictingId() async throws {
        try await listDao.saveList(TestData.listEntity(id: "l1", name: "First"))
        try await listDao.saveList(TestData.listEntity(id: "l1", name: "Second"))

        let rows = try await listDao.listsWithItemCount(accountId: nil)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "Second")
    }

    func testUpdateListWritesTheNewName() async throws {
        let entity = TestData.listEntity(id: "l1", name: "Before")
        try await listDao.insertList(entity)

        try await listDao.updateList(entity.with { $0.name = "After" })

        let list = try await listDao.list(id: "l1")
        XCTAssertEqual(list?.name, "After")
    }

    func testInsertListWithItemsWritesBothInOneCall() async throws {
        try await listDao.insertListWithItems(
            TestData.listEntity(id: "l1"),
            items: [TestData.itemEntity(id: "i1", listId: "l1"), TestData.itemEntity(id: "i2", listId: "l1")])

        let list = try await listDao.list(id: "l1")
        let items = try await itemDao.itemsByListIdOnce("l1")
        XCTAssertEqual(list?.id, "l1")
        XCTAssertEqual(items.count, 2)
    }

    func testInsertListWithItemsAcceptsAnEmptyItemList() async throws {
        try await listDao.insertListWithItems(TestData.listEntity(id: "l1"), items: [])

        let list = try await listDao.list(id: "l1")
        let items = try await itemDao.itemsByListIdOnce("l1")
        XCTAssertEqual(list?.id, "l1")
        XCTAssertTrue(items.isEmpty)
    }

    // Proves it is one transaction: the item references a list that doesn't
    // exist, so the foreign key rejects it, and the list insert rolls back too.
    func testInsertListWithItemsRollsBackTheListWhenItsItemsAreRejected() async throws {
        var failed = false
        do {
            try await listDao.insertListWithItems(
                TestData.listEntity(id: "l1"),
                items: [TestData.itemEntity(id: "i1", listId: "does-not-exist")])
        } catch {
            failed = true
        }

        let list = try await listDao.list(id: "l1")
        XCTAssertTrue(failed, "expected the foreign key to reject the item")
        XCTAssertNil(list, "the list insert should have rolled back")
    }

    func testMostRecentlyEditedCountsItemActivityDeletedItemsIncluded() async throws {
        try await listDao.insertList(TestData.listEntity(id: "renamed", createdAt: 1, updatedAt: 5_000))
        try await listDao.insertList(TestData.listEntity(id: "busy", createdAt: 2, updatedAt: 100))
        try await itemDao.insertItem(TestData.itemEntity(id: "i1", listId: "busy", updatedAt: 9_000))

        let first = try await listDao.mostRecentlyEdited(accountId: nil)
        XCTAssertEqual(first?.id, "busy")

        // Deleting an item is an edit too.
        try await itemDao.insertItem(
            TestData.itemEntity(id: "i2", listId: "renamed", updatedAt: 9_500).with { $0.deletedAt = 9_500 })
        let second = try await listDao.mostRecentlyEdited(accountId: nil)
        XCTAssertEqual(second?.id, "renamed")
    }

    func testMostRecentlyEditedSortsAnEmptyListByItsOwnUpdatedAtAndTiesByCreatedAt() async throws {
        try await listDao.insertList(TestData.listEntity(id: "old", createdAt: 1, updatedAt: 10))
        try await listDao.insertList(TestData.listEntity(id: "newer", createdAt: 2, updatedAt: 10))
        let first = try await listDao.mostRecentlyEdited(accountId: nil)
        XCTAssertEqual(first?.id, "newer")

        try await listDao.insertList(TestData.listEntity(id: "latest", createdAt: 1, updatedAt: 11))
        let second = try await listDao.mostRecentlyEdited(accountId: nil)
        XCTAssertEqual(second?.id, "latest")
    }

    func testMostRecentlyEditedKeepsItsOwnerScopingAndSkipsDeletedLists() async throws {
        try await listDao.insertList(TestData.listEntity(id: "guest", updatedAt: 1))
        try await listDao.insertList(TestData.listEntity(id: "mine", updatedAt: 2).with { $0.accountId = "u1" })
        try await listDao.insertList(TestData.listEntity(id: "theirs", updatedAt: 3).with { $0.accountId = "u2" })
        try await listDao.insertList(TestData.listEntity(id: "gone", updatedAt: 4).with {
            $0.accountId = "u1"
            $0.deletedAt = 5
        })
        try await listDao.insertList(TestData.listEntity(id: "orphan", updatedAt: 6).with { $0.shareCode = "ABC234" })

        let guest = try await listDao.mostRecentlyEdited(accountId: nil)
        let mine = try await listDao.mostRecentlyEdited(accountId: "u1")
        let nobody = try await listDao.mostRecentlyEdited(accountId: "nobody")
        XCTAssertEqual(guest?.id, "guest")
        XCTAssertEqual(mine?.id, "mine")
        XCTAssertNil(nobody)
    }

    // MARK: - iOS additions

    // The rule behind saveList: an existing row is UPDATEd, never REPLACEd, so the
    // CASCADE never fires and the list keeps its items.
    func testUpdatingAListKeepsItsItems() async throws {
        let list = TestData.listEntity(id: "l1", name: "Before")
        try await listDao.insertListWithItems(
            list, items: [TestData.itemEntity(id: "i1", listId: "l1"), TestData.itemEntity(id: "i2", listId: "l1")])

        try await listDao.saveList(list.with { $0.name = "After"; $0.pendingSync = true })
        try await listDao.updateList(list.with { $0.name = "After again" })
        try await listDao.insertListWithItems(list.with { $0.name = "Restored" }, items: [])

        let stored = try await listDao.list(id: "l1")
        let items = try await itemDao.itemsByListIdOnce("l1")
        XCTAssertEqual(stored?.name, "Restored")
        XCTAssertEqual(Set(items.map(\.id)), ["i1", "i2"])
    }

    func testInsertListRejectsAnExistingId() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1"))
        do {
            try await listDao.insertList(TestData.listEntity(id: "l1", name: "Again"))
            XCTFail("a plain INSERT of an existing id must fail")
        } catch {}
    }

    func testSoftDeleteListIfEmptyIgnoresTombstonedItems() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1").with { $0.accountId = "u1" })
        try await itemDao.insertItem(TestData.itemEntity(id: "i1", listId: "l1").with { $0.deletedAt = 1 })

        let changed = try await listDao.softDeleteListIfEmpty(id: "l1", now: 42)
        let raw = try await listDao.listRaw(id: "l1")
        let live = try await listDao.list(id: "l1")

        XCTAssertEqual(changed, 1)
        XCTAssertEqual(raw?.deletedAt, 42)
        XCTAssertEqual(raw?.updatedAt, 42)
        XCTAssertEqual(raw?.pendingSync, true)
        XCTAssertNil(live)
    }

    func testMarkListSyncedOnlyClearsTheFlagForTheSameSnapshot() async throws {
        try await listDao.insertList(TestData.listEntity(id: "l1", updatedAt: 10).with {
            $0.accountId = "u1"
            $0.pendingSync = true
        })

        try await listDao.markListSynced(id: "l1", updatedAt: 9)
        let stillPending = try await listDao.countPendingAccountLists(accountId: "u1")
        try await listDao.markListSynced(id: "l1", updatedAt: 10)
        let nowPending = try await listDao.countPendingAccountLists(accountId: "u1")

        XCTAssertEqual(stillPending, 1)
        XCTAssertEqual(nowPending, 0)
    }

    func testClaimDeviceListsMovesGuestListsAndQueuesTheirItems() async throws {
        try await listDao.insertList(TestData.listEntity(id: "guest"))
        try await itemDao.insertItem(TestData.itemEntity(id: "i1", listId: "guest"))
        try await listDao.insertList(TestData.listEntity(id: "theirs").with { $0.accountId = "u2" })
        try await listDao.insertList(TestData.listEntity(id: "orphan").with { $0.shareCode = "ABC234" })

        let claimed = try await listDao.claimDeviceLists(userId: "u1", includeOwnerlessShared: true)

        let ids = try await catalogIds("u1")
        let theirs = try await listDao.listRaw(id: "theirs")
        let pendingItems = try await itemDao.pendingSyncItemsForAccount("u1")
        XCTAssertEqual(claimed, 1)
        XCTAssertEqual(Set(ids), ["guest", "orphan"])
        XCTAssertNil(theirs)
        XCTAssertEqual(pendingItems.map(\.id), ["i1"])
    }

    func testReleaseClaimsReturnsListsToOwnerless() async throws {
        try await listDao.insertList(TestData.listEntity(id: "a").with { $0.accountId = "u1"; $0.shareCode = "AAA" })
        try await listDao.insertList(TestData.listEntity(id: "b").with { $0.accountId = "u1"; $0.shareCode = "BBB" })

        try await listDao.releaseClaims(ids: ["a"], userId: "u1")

        let ownerless = try await listDao.ownerlessSharedListIds()
        XCTAssertEqual(ownerless, ["a"])
    }

    func testDeleteAccountListsKeepsGuestLists() async throws {
        try await listDao.insertList(TestData.listEntity(id: "guest"))
        try await listDao.insertList(TestData.listEntity(id: "mine").with { $0.accountId = "u1" })
        try await listDao.insertList(TestData.listEntity(id: "orphan").with { $0.shareCode = "ABC234" })

        try await listDao.deleteAccountLists()

        let guestIds = try await listDao.guestListIds()
        XCTAssertEqual(guestIds, ["guest"])
    }
}
