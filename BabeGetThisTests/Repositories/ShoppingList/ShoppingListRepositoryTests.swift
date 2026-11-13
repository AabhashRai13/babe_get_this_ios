import GRDB
import XCTest
@testable import BabeGetThis

/// Port of Android's ShoppingListRepositoryTest (minus delete/undo, which is F07, and the
/// PIN lock cases, out of iOS v1) and the non-delete ShoppingListRepositorySharedTest cases
/// (minus the reminder one, out of iOS v1). Real in-memory database, not mocked DAOs.
final class ShoppingListRepositoryTests: XCTestCase {
    private var db: AppDatabase!
    private var kicker: CountingSyncKicker!
    private var kicks: Int { kicker.kicks }

    // Everything below the ownership section runs as a guest, which is how
    // these tests behaved before lists had owners.
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

    private func seed(_ id: String, accountId: String? = nil, shareCode: String? = nil) async throws {
        try await db.lists.insertList(TestData.listEntity(id: id).with {
            $0.accountId = accountId
            $0.shareCode = shareCode
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

    private func error<T>(_ result: Result<T, AppError>) -> AppError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    private func isValidation(_ error: AppError?) -> Bool {
        if case .validation = error { return true }
        return false
    }

    private func allLists(_ repo: ShoppingListRepository? = nil) async throws -> [ShoppingList] {
        try await firstValue((repo ?? repository).allLists())
    }

    /// The row, tombstones included (Android `getListRaw(id)!!`).
    private func storedList(_ id: String, line: UInt = #line) async throws -> ShoppingListRecord {
        let raw = try await db.lists.listRaw(id: id)
        return try XCTUnwrap(raw, "no row \(id)", line: line)
    }

    private func items(_ listId: String) async throws -> [ShoppingItemRecord] {
        try await db.items.itemsByListIdOnce(listId)
    }

    // MARK: - ownership: who sees which lists (docs/technical-decisions/008)

    func testGuestsSeeOnlyGuestLists() async throws {
        try await seed("guest")
        try await seed("mine", accountId: "u1")
        // A shared replica whose owner was lost before ownership existed.
        try await seed("orphan", shareCode: "ABC234")

        let ids = try await allLists().map(\.id)
        XCTAssertEqual(["guest"], ids)
    }

    func testASignedInUserSeesOnlyTheirAccountsLists() async throws {
        try await seed("guest")
        try await seed("mine", accountId: "u1")
        try await seed("theirs", accountId: "u2")

        let ids = try await allLists(repositoryAs(authStateFor("u1"))).map(\.id)
        XCTAssertEqual(["mine"], ids)
    }

    func testAnExpiredSessionStillSeesTheAccountsLists() async throws {
        try await seed("guest")
        try await seed("mine", accountId: "u1")

        let lists = try await allLists(repositoryAs(authStateFor("u1", expired: true)))

        XCTAssertEqual(["mine"], lists.map(\.id))
    }

    // The reason allLists() follows the data owner: signing in or out swaps the lists on
    // screen without anyone asking, and nothing of the previous owner's arrives afterwards.
    func testSigningInAndOutSwapsTheListsOnTheSameStream() async throws {
        try await seed("guest")
        try await seed("mine", accountId: "u1")
        try await seed("theirs", accountId: "u2")
        let auth = authStateFor(nil)
        var lists = repositoryAs(auth).allLists().makeAsyncIterator()

        let asGuest = try await lists.next()
        XCTAssertEqual(asGuest?.map(\.id), ["guest"])

        auth.login(token: "token-u1", userId: "u1", userName: "Ann", userEmail: "ann@example.com")
        let signedIn = try await lists.next()
        XCTAssertEqual(signedIn?.map(\.id), ["mine"])

        auth.logout()
        let signedOut = try await lists.next()
        XCTAssertEqual(signedOut?.map(\.id), ["guest"])
    }

    func testIsAccountListTellsAccountListsFromGuestLists() async throws {
        try await seed("guest")
        try await seed("mine", accountId: "u1")

        let guest = try await repository.isAccountList("guest")
        let mine = try await repository.isAccountList("mine")
        let missing = try await repository.isAccountList("missing")
        XCTAssertFalse(guest)
        XCTAssertTrue(mine)
        XCTAssertFalse(missing)
    }

    func testAGuestsNewListHasNoOwnerAndIsNotQueued() async throws {
        let id = try data(try await repository.createList(name: "Groceries"))

        let row = try await storedList(id)
        XCTAssertNil(row.accountId)
        XCTAssertFalse(row.pendingSync)
        XCTAssertEqual(0, kicks)
    }

    func testASignedInUsersNewListIsOwnedAndQueued() async throws {
        let id = try data(try await repositoryAs(authStateFor("u1")).createList(name: "Groceries"))

        let row = try await storedList(id)
        XCTAssertEqual("u1", row.accountId)
        XCTAssertTrue(row.pendingSync)
        XCTAssertEqual(1, kicks)
    }

    // In a store with no signal and a dead token: the list must still belong to
    // the account and wait in the outbox for the next sign-in.
    func testAVoiceListMadeWhileExpiredIsOwnedAndQueuedWithItsItems() async throws {
        let repo = repositoryAs(authStateFor("u1", expired: true))

        let id = try data(try await repo.createListWithItems(name: "Shop", drafts: [TestData.draft(name: "Milk")]))

        let row = try await storedList(id)
        XCTAssertEqual("u1", row.accountId)
        XCTAssertTrue(row.pendingSync)
        let stored = try await items(id)
        XCTAssertEqual(1, stored.count)
        XCTAssertTrue(try XCTUnwrap(stored.first).pendingSync)
        XCTAssertEqual(1, kicks)
    }

    func testAGuestsVoiceListAndItsItemsAreNotQueued() async throws {
        let id = try data(try await repository.createListWithItems(name: "Shop", drafts: [TestData.draft(name: "Milk")]))

        let row = try await storedList(id)
        XCTAssertNil(row.accountId)
        let stored = try await items(id)
        XCTAssertEqual(1, stored.count)
        XCTAssertFalse(try XCTUnwrap(stored.first).pendingSync)
        XCTAssertEqual(0, kicks)
    }

    // MARK: - createList

    func testCreateListStoresTheListAndReturnsItsId() async throws {
        let id = try data(try await repository.createList(name: "Groceries"))

        let lists = try await allLists()
        XCTAssertEqual(1, lists.count)
        XCTAssertEqual(id, lists.first?.id)
        XCTAssertEqual("Groceries", lists.first?.name)
    }

    func testCreateListTrimsTheName() async throws {
        _ = try await repository.createList(name: "  Groceries  ")

        let lists = try await allLists()
        XCTAssertEqual(["Groceries"], lists.map(\.name))
    }

    func testCreateListRejectsABlankName() async throws {
        let result = try await repository.createList(name: "   ")

        XCTAssertTrue(isValidation(error(result)), "got \(result)")
        let lists = try await allLists()
        XCTAssertTrue(lists.isEmpty, "nothing should have been stored")
    }

    func testCreateListRejectsAnEmptyName() async throws {
        let result = try await repository.createList(name: "")

        XCTAssertTrue(isValidation(error(result)), "got \(result)")
    }

    // MARK: - createListWithItems / draftsToItems

    func testCreateListWithItemsStoresTheListAndItsDrafts() async throws {
        let id = try data(try await repository.createListWithItems(
            name: "Voice list",
            drafts: [TestData.draft(name: "Milk"), TestData.draft(name: "Eggs")]))

        let names = try await items(id).map(\.name)
        XCTAssertEqual(["Milk", "Eggs"], Set(names))
    }

    func testCreateListWithItemsAcceptsNoDrafts() async throws {
        let id = try data(try await repository.createListWithItems(name: "Empty", drafts: []))

        let stored = try await items(id)
        XCTAssertTrue(stored.isEmpty)
    }

    func testDraftQuantityNullBecomesEmptyStringToMatchTypedItems() async throws {
        let id = try data(try await repository.createListWithItems(
            name: "L", drafts: [TestData.draft(name: "Milk", quantity: nil)]))

        let stored = try await items(id)
        XCTAssertEqual([""], stored.map(\.quantity))
    }

    // The trust-boundary guard: the backend supplies a category id, and we keep
    // it ONLY if it names a row we actually have.
    func testKnownDraftCategoryIsKept() async throws {
        try await db.categories.insertCategory(TestData.categoryEntity(id: "cat-dairy"))

        let id = try data(try await repository.createListWithItems(
            name: "L", drafts: [TestData.draft(name: "Milk", category: "cat-dairy")]))

        let stored = try await items(id)
        XCTAssertEqual(["cat-dairy"], stored.map(\.categoryId))
    }

    func testUnknownDraftCategoryIsDropped() async throws {
        let id = try data(try await repository.createListWithItems(
            name: "L", drafts: [TestData.draft(name: "Milk", category: "cat-not-real")]))

        let stored = try await items(id)
        XCTAssertEqual(1, stored.count)
        XCTAssertNil(stored.first?.categoryId)
    }

    func testNullDraftCategoryStaysNull() async throws {
        let id = try data(try await repository.createListWithItems(
            name: "L", drafts: [TestData.draft(name: "Milk", category: nil)]))

        let stored = try await items(id)
        XCTAssertEqual(1, stored.count)
        XCTAssertNil(stored.first?.categoryId)
    }

    func testDraftNoteAndShopAreCarriedThrough() async throws {
        let id = try data(try await repository.createListWithItems(
            name: "L", drafts: [TestData.draft(name: "Milk", note: "semi-skimmed", shop: "Aldi")]))

        let stored = try await items(id)
        let item = try XCTUnwrap(stored.first)
        XCTAssertEqual("semi-skimmed", item.note)
        XCTAssertEqual("Aldi", item.shop)
    }

    func testCreateListWithItemsRejectsABlankNameBeforeWritingAnything() async throws {
        let result = try await repository.createListWithItems(name: "  ", drafts: [TestData.draft()])

        XCTAssertTrue(isValidation(error(result)), "got \(result)")
        let lists = try await allLists()
        XCTAssertTrue(lists.isEmpty)
    }

    // MARK: - addItemsToList

    func testAddItemsToListAppendsToAnExistingList() async throws {
        let id = try data(try await repository.createList(name: "Groceries"))
        try await db.items.insertItem(TestData.itemEntity(id: "existing", listId: id))

        _ = try await repository.addItemsToList(listId: id, drafts: [TestData.draft(name: "Eggs")])

        let count = try await items(id).count
        XCTAssertEqual(2, count)
    }

    func testAddItemsToListReturnsTheListId() async throws {
        let id = try data(try await repository.createList(name: "Groceries"))

        let returned = try data(try await repository.addItemsToList(listId: id, drafts: [TestData.draft()]))
        XCTAssertEqual(id, returned)
    }

    func testAddItemsToListWithNoDraftsIsANoOp() async throws {
        let id = try data(try await repository.createList(name: "Groceries"))

        _ = try await repository.addItemsToList(listId: id, drafts: [])

        let stored = try await items(id)
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - updateListName

    func testUpdateListNameWritesTheNewName() async throws {
        let id = try data(try await repository.createList(name: "Before"))

        _ = try await repository.updateListName(listId: id, newName: "After")

        let names = try await allLists().map(\.name)
        XCTAssertEqual(["After"], names)
    }

    func testUpdateListNameTrims() async throws {
        let id = try data(try await repository.createList(name: "Before"))

        _ = try await repository.updateListName(listId: id, newName: "  After  ")

        let names = try await allLists().map(\.name)
        XCTAssertEqual(["After"], names)
    }

    func testUpdateListNameRejectsABlankName() async throws {
        let id = try data(try await repository.createList(name: "Before"))

        let result = try await repository.updateListName(listId: id, newName: " ")

        XCTAssertTrue(isValidation(error(result)), "got \(result)")
        let names = try await allLists().map(\.name)
        XCTAssertEqual(["Before"], names)
    }

    // A bare error would reach safeCall as .unknown and show generic copy to the user.
    func testUpdateListNameReportsNotFoundForAMissingList() async throws {
        let result = try await repository.updateListName(listId: "nope", newName: "X")

        guard case .notFound = error(result) else { return XCTFail("got \(result)") }
    }

    // MARK: - streams

    func testAllListsIsEmptyToStart() async throws {
        let lists = try await allLists()
        XCTAssertTrue(lists.isEmpty)
    }

    func testListByIdEmitsNilForAMissingId() async throws {
        let list = try await firstValue(repository.listById("nope"))
        XCTAssertNil(list)
    }

    // MARK: - failure mapping

    // A real constraint violation: the items reference a list that doesn't exist,
    // so the foreign key rejects them. safeCall must turn the GRDB error into
    // .database rather than letting it escape.
    func testADatabaseConstraintFailureComesBackAsDatabaseError() async throws {
        let result = try await repository.addItemsToList(listId: "no-such-list", drafts: [TestData.draft()])

        guard case .database = error(result) else { return XCTFail("expected a database error, got \(result)") }
    }

    func testAFailedWriteLeavesNothingBehind() async throws {
        _ = try await repository.addItemsToList(listId: "no-such-list", drafts: [TestData.draft()])

        let stored = try await items("no-such-list")
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - shared and account lists (Android ShoppingListRepositorySharedTest)
    //
    // Dirty flags and push kicks. Local-only behaviour must not change; a test pins that.

    private func sharedList(_ id: String = "list-1") -> ShoppingListRecord {
        ShoppingListRecord(
            id: id, name: "Groceries", createdAt: 1, updatedAt: 2, shareCode: "ABC234", accountId: "u1")
    }

    private var signedIn: ShoppingListRepository { repositoryAs(authStateFor("u1")) }

    func testGetShareCodeReflectsTheRowsLiveShareState() async throws {
        try await db.lists.insertList(sharedList())

        let code = try await firstValue(signedIn.shareCode(listId: "list-1"))
        let other = try await firstValue(signedIn.shareCode(listId: "other"))
        XCTAssertEqual("ABC234", code)
        XCTAssertNil(other)
    }

    func testRenamingASharedListMarksItDirtyAndKicksAPush() async throws {
        try await db.lists.insertList(sharedList())

        _ = try await signedIn.updateListName(listId: "list-1", newName: "Weekend shop")

        let row = try await storedList("list-1")
        XCTAssertTrue(row.pendingSync)
        XCTAssertEqual("Weekend shop", row.name)
        XCTAssertEqual(1, kicks)
    }

    func testRenamingALocalOnlyListStaysCleanAndQuiet() async throws {
        try await db.lists.insertList(sharedList().with {
            $0.shareCode = nil
            $0.accountId = nil
        })

        _ = try await signedIn.updateListName(listId: "list-1", newName: "Weekend shop")

        let row = try await storedList("list-1")
        XCTAssertFalse(row.pendingSync)
        XCTAssertEqual(0, kicks)
    }

    func testVoiceItemsAddedToASharedListArriveDirtyAndKickAPush() async throws {
        try await db.lists.insertList(sharedList())

        _ = try await signedIn.addItemsToList(listId: "list-1", drafts: [TestData.draft(name: "Milk")])

        let stored = try await items("list-1")
        XCTAssertEqual(1, stored.count)
        XCTAssertTrue(try XCTUnwrap(stored.first).pendingSync)
        XCTAssertEqual(1, kicks)
    }

    // Unshared account lists sync too (docs/technical-decisions/008).
    func testRenamingAnUnsharedAccountListMarksItDirtyAndKicks() async throws {
        try await db.lists.insertList(sharedList().with { $0.shareCode = nil })

        _ = try await signedIn.updateListName(listId: "list-1", newName: "Weekend shop")

        let row = try await storedList("list-1")
        XCTAssertTrue(row.pendingSync)
        XCTAssertEqual(1, kicks)
    }
}
