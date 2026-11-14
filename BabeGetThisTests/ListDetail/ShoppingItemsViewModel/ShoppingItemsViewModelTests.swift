import XCTest
@testable import BabeGetThis

/// Stands in for `CategoryRepository` when creating a category: returns the result a test set
/// and records the names it was asked to create.
private final class FakeCategoryPickerSource: CategoryPickerSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _added: [String] = []
    let addResult: Result<String, AppError>

    var added: [String] { lock.withLock { _added } }

    init(addResult: Result<String, AppError>) {
        self.addResult = addResult
    }

    func allCategories() -> AsyncThrowingStream<[ProductCategory], any Error> {
        AsyncThrowingStream { _ in }
    }

    func addCategory(name: String) async throws -> Result<String, AppError> {
        lock.withLock { _added.append(name) }
        return addResult
    }
}

/// Android `listRepository.addItemsToList`, mocked: records each call and returns `result`.
private final class RecordingListItemsAdder: ListItemsAdding, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(listId: String, drafts: [ItemDraft])] = []
    let result: Result<String, AppError>

    var calls: [(listId: String, drafts: [ItemDraft])] { lock.withLock { _calls } }

    init(result: Result<String, AppError>) {
        self.result = result
    }

    func addItemsToList(listId: String, drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        lock.withLock { _calls.append((listId, drafts)) }
        return result
    }
}

/// Port of the core cases of Android's ShoppingItemsViewModelTest (DET-14). On iOS the screen's
/// state is split, so each case runs against the type that owns it: `ListDetailViewModel`
/// (items, writes, undo), `ListDetailChromeModel` (auth gate, list name, share text),
/// `ListLeaveGuard` (leaving an empty list, teardown) and `CategoryPickerModel` (new categories).
/// The list-completed, share-live, realtime, lock, reminder, Got This and telemetry cases live
/// elsewhere or are out of iOS v1.
@MainActor
final class ShoppingItemsViewModelTests: XCTestCase {
    private var source: FakeListDetailItemsSource!
    private var haptics: RecordingHapticPlayer!
    private var cleaner: FakeListLeaveCleaner!
    private var leaveGuard: ListLeaveGuard!
    private var observers: [Task<Void, Never>] = []

    override func setUp() async throws {
        source = FakeListDetailItemsSource()
        haptics = RecordingHapticPlayer()
        cleaner = FakeListLeaveCleaner()
        leaveGuard = ListLeaveGuard(listId: "L1", cleaner: cleaner)
    }

    override func tearDown() async throws {
        observers.forEach { $0.cancel() }
        observers = []
    }

    /// Android's `buildViewModel()`: the view model starts collecting straight away.
    private func buildViewModel() -> ListDetailViewModel {
        let vm = ListDetailViewModel(listId: "L1", source: source, haptics: haptics)
        observers.append(Task { await vm.observeItems() })
        return vm
    }

    /// `itemsFlow.value = items`, then waits until the view model has applied it.
    private func emit(_ items: [StoredShoppingItem], to vm: ListDetailViewModel,
                      file: StaticString = #filePath, line: UInt = #line) async {
        source.send(items)
        await listDetailEventually("items never reached the view model", file: file, line: line) {
            vm.storedItems == items
        }
    }

    private func item(_ id: String, isPickedUp: Bool = false, name: String? = nil) -> StoredShoppingItem {
        TestData.storedItem(id, isPickedUp: isPickedUp, name: name)
    }

    private func chrome(_ state: AuthState, items: @escaping @MainActor () -> [ShoppingItem] = { [] })
        -> ListDetailChromeModel {
        ListDetailChromeModel(listName: "Groceries", authState: { state }, haptics: haptics, items: items)
    }

    /// The screen's `.task`s on the leave path: items and share state, then waits for the items.
    private func loadedForLeaving(items: [StoredShoppingItem], shareCode: String? = nil)
        async -> ListDetailViewModel {
        source.send(items)
        cleaner.sendShareCode(shareCode)
        let vm = buildViewModel()
        let leaveGuard = leaveGuard!
        observers.append(Task { await leaveGuard.observeShareCode() })
        await listDetailEventually { vm.hasLoaded }
        await Task.yield()
        return vm
    }

    // MARK: Delete + Undo

    func testDeleteItemCachesTheItemCallsRepositoryAndOffersUndoWithItemName() async {
        let vm = buildViewModel()
        await emit([item("1", name: "Milk")], to: vm)

        await vm.delete("1")

        XCTAssertEqual(source.deleted, ["1"])
        XCTAssertEqual(vm.undoMessage, "Milk deleted")
        XCTAssertEqual(vm.pendingUndo?.name, "Milk")
    }

    func testUndoDeleteItemRestoresThePreviouslyDeletedItemViaRepository() async {
        let target = item("1", name: "Milk")
        let vm = buildViewModel()
        await emit([target], to: vm)

        await vm.delete("1")
        await vm.undoDelete()

        XCTAssertEqual(source.restored, [target])
        XCTAssertNil(vm.pendingUndo)
    }

    func testUndoDeleteItemWithNoPendingDeleteIsANoOp() async {
        let vm = buildViewModel()

        await vm.undoDelete()

        XCTAssertTrue(source.restored.isEmpty)
    }

    func testDeleteItemOnRepositoryErrorShowsTheErrorAndDoesNotCacheForUndo() async {
        source.deleteResult = .failure(.database("boom"))
        let vm = buildViewModel()
        await emit([item("1", name: "Milk")], to: vm)

        await vm.delete("1")

        XCTAssertEqual(vm.errorMessage, "boom")
        XCTAssertNil(vm.undoMessage)
        // No undo offered, no restore allowed.
        await vm.undoDelete()
        XCTAssertTrue(source.restored.isEmpty)
    }

    func testDeleteItemOffersNoUndoWhenTheItemWasNeverInState() async {
        let vm = buildViewModel()
        await emit([], to: vm)

        await vm.delete("ghost")

        XCTAssertEqual(source.deleted, ["ghost"])
        XCTAssertNil(vm.undoMessage)
        XCTAssertNil(vm.pendingUndo)
    }

    func testAFailedRestoreKeepsTheCacheSoUndoCanBeRetried() async {
        let target = item("1", name: "Milk")
        let vm = buildViewModel()
        await emit([target], to: vm)
        await vm.delete("1")

        source.restoreResult = .failure(.database("restore failed"))
        await vm.undoDelete()
        XCTAssertEqual(vm.errorMessage, "restore failed")
        XCTAssertEqual(vm.pendingUndo, target)

        source.restoreResult = .success(())
        await vm.undoDelete()
        XCTAssertEqual(source.restored, [target, target])
        XCTAssertNil(vm.pendingUndo)
    }

    // MARK: Leaving an empty list (ListLeaveGuard)

    func testLeavingAnEmptyListWouldDeleteIt() async {
        let vm = await loadedForLeaving(items: [])

        await listDetailEventually { self.leaveGuard.leavingDeletesList(vm) }
    }

    func testLeavingAListWithItemsKeepsIt() async {
        let vm = await loadedForLeaving(items: [TestData.storedItem("1")])
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(leaveGuard.leavingDeletesList(vm))
    }

    // Shared lists are never auto-deleted (the partner may still be using them), so
    // asking would be untrue there. Goes through the transition: an unknown share state
    // also answers false, so only "unshared → true, then shared → false" proves the code
    // is read. It also covers a list shared while the screen is open.
    func testLeavingAnEmptySharedListKeepsIt() async {
        let vm = await loadedForLeaving(items: [], shareCode: nil)
        await listDetailEventually("unshared and empty: leaving deletes it") {
            self.leaveGuard.leavingDeletesList(vm)
        }

        cleaner.sendShareCode("ABC123")

        await listDetailEventually("shared now: leaving keeps it") {
            !self.leaveGuard.leavingDeletesList(vm)
        }
    }

    func testAddingTheFirstItemStopsTheQuestion() async {
        let vm = await loadedForLeaving(items: [])
        await listDetailEventually { self.leaveGuard.leavingDeletesList(vm) }

        source.send([TestData.storedItem("1")])

        await listDetailEventually { !self.leaveGuard.leavingDeletesList(vm) }
    }

    // Until the database answers, the list's contents are unknown; assuming "empty"
    // would ask on a quick back press from a full list.
    func testNothingIsClaimedBeforeTheItemsHaveLoaded() async {
        cleaner.sendShareCode(nil)
        let vm = buildViewModel()
        let leaveGuard = leaveGuard!
        observers.append(Task { await leaveGuard.observeShareCode() })
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(leaveGuard.leavingDeletesList(vm))

        // The share state was read: once the (empty) items arrive, the answer flips.
        source.send([])
        await listDetailEventually { leaveGuard.leavingDeletesList(vm) }
    }

    // MARK: Edit flow

    func testEditKeepsIdListIdCreatedAtAndPickedUp() async throws {
        let db = try AppDatabase.inMemory()
        try await db.lists.insertList(TestData.listEntity(id: "list-1"))
        try await db.items.insertItem(TestData.itemEntity(
            id: "i1", name: "Milk", quantity: "2", isPickedUp: true, categoryId: "cat-dairy-eggs",
            shop: "Aldi", note: "semi", createdAt: 5_000, updatedAt: 5_000))
        let repository = ShoppingItemRepository(
            itemDao: db.items, categoryDao: db.categories, listDao: db.lists,
            syncKicker: CountingSyncKicker(), safeCall: SafeCall(reporter: SilentAppErrorReporter()))
        let vm = ListDetailViewModel(listId: "list-1", source: repository, haptics: RecordingHapticPlayer())
        let observation = Task { await vm.observeItems() }
        defer { observation.cancel() }
        await listDetailEventually { vm.items.count == 1 }

        // Android sets a new value for every editable field and checks each one is written.
        var draft = ItemDraft(editing: try XCTUnwrap(vm.items.first))
        draft.name = "  Oat milk  "
        draft.quantity = "3"
        draft.shop = "new shop"
        draft.note = "new note"
        draft.categoryId = "cat-bakery-bread"
        let saved = await vm.edit("i1", with: draft)
        XCTAssertTrue(saved)

        let row = try await db.items.itemRaw(id: "i1")
        XCTAssertEqual(row?.id, "i1")
        XCTAssertEqual(row?.listId, "list-1")
        XCTAssertEqual(row?.createdAt, 5_000)
        XCTAssertEqual(row?.isPickedUp, true)
        XCTAssertEqual(row?.name, "Oat milk")
        XCTAssertEqual(row?.quantity, "3")
        XCTAssertEqual(row?.shop, "new shop")
        XCTAssertEqual(row?.note, "new note")
        XCTAssertEqual(row?.categoryId, "cat-bakery-bread")
    }

    // iOS: a blank shop and no category are stored as nil, not as "" or a stale value.
    func testEditStoresABlankShopAndNoCategoryAsNil() async throws {
        let db = try AppDatabase.inMemory()
        try await db.lists.insertList(TestData.listEntity(id: "list-1"))
        try await db.items.insertItem(TestData.itemEntity(
            id: "i1", name: "Milk", categoryId: "cat-dairy-eggs", shop: "Aldi"))
        let repository = ShoppingItemRepository(
            itemDao: db.items, categoryDao: db.categories, listDao: db.lists,
            syncKicker: CountingSyncKicker(), safeCall: SafeCall(reporter: SilentAppErrorReporter()))
        let vm = ListDetailViewModel(listId: "list-1", source: repository, haptics: RecordingHapticPlayer())
        let observation = Task { await vm.observeItems() }
        defer { observation.cancel() }
        await listDetailEventually { vm.items.count == 1 }

        var draft = ItemDraft(editing: try XCTUnwrap(vm.items.first))
        draft.shop = "   "
        draft.categoryId = nil
        let saved = await vm.edit("i1", with: draft)
        XCTAssertTrue(saved)

        let row = try await db.items.itemRaw(id: "i1")
        XCTAssertNil(row?.shop)
        XCTAssertNil(row?.categoryId)
    }

    func testEditItemWithUnknownItemIdDoesNotCallRepository() async {
        let vm = buildViewModel()
        await emit([item("1")], to: vm)

        let saved = await vm.edit("does-not-exist", with: ItemDraft(name: "x", quantity: "1"))

        XCTAssertFalse(saved)
        XCTAssertTrue(source.updated.isEmpty)
    }

    // iOS: the edit sheet closes (and the screen's `editingItem` clears) when `edit` returns true.
    func testEditItemOnSuccessClosesTheEditSheet() async {
        let vm = buildViewModel()
        await emit([item("1")], to: vm)

        let saved = await vm.edit("1", with: ItemDraft(name: "renamed", quantity: "1"))

        XCTAssertTrue(saved)
        XCTAssertEqual(source.updated.map(\.name), ["renamed"])
        XCTAssertNil(vm.errorMessage)
    }

    func testEditFailureKeepsTheDialogOpenAndShowsTheError() async {
        source.updateResult = .failure(.database("write failed"))
        let vm = buildViewModel()
        await emit([TestData.storedItem("a")], to: vm)

        let saved = await vm.edit("a", with: ItemDraft(editing: vm.items[0]))
        XCTAssertFalse(saved)
        XCTAssertEqual(vm.errorMessage, "write failed")
    }

    // MARK: Auth gating (ListDetailChromeModel)

    func testIsAuthenticatedReflectsTheAuthState() {
        let model = chrome(.authenticated(userId: "u1"))

        model.voiceFabTapped()

        XCTAssertTrue(model.isVoicePresented)
        XCTAssertNil(model.authPrompt)
    }

    func testIsAuthenticatedIsFalseWhenUnauthenticated() {
        let model = chrome(.unauthenticated)

        model.voiceFabTapped()

        XCTAssertFalse(model.isVoicePresented)
        XCTAssertEqual(model.authPrompt, .voice)
    }

    // MARK: Derived state

    func testUiStateSplitsActiveFromCompleted() async {
        let vm = buildViewModel()
        await emit([item("1"), item("2", isPickedUp: true), item("3")], to: vm)

        XCTAssertEqual(vm.activeItems.map(\.id), ["1", "3"])
        XCTAssertEqual(vm.completedItems.map(\.id), ["2"])
        XCTAssertEqual(vm.totalCount, 3)
        XCTAssertEqual(vm.pickedUpCount, 1)
        XCTAssertEqual(vm.percent, 33)
    }

    func testUiStateIsEmptyForAnEmptyList() async {
        let vm = buildViewModel()
        await emit([], to: vm)

        XCTAssertTrue(vm.isEmpty)
        XCTAssertTrue(vm.activeItems.isEmpty)
        XCTAssertTrue(vm.completedItems.isEmpty)
        XCTAssertTrue(vm.activeGroups.isEmpty)
    }

    func testActiveSectionsGroupByShopAndBucketMissingShopsUnderNil() async throws {
        let vm = buildViewModel()
        var a = item("a"), b = item("b"), c = item("c")
        a.shop = "Aldi"
        b.shop = "Aldi"
        c.shop = nil
        await emit([a, b, c], to: vm)

        let aldi = try XCTUnwrap(vm.activeGroups.first { $0.shop == "Aldi" })
        let noShop = try XCTUnwrap(vm.activeGroups.first { $0.shop == nil })
        XCTAssertEqual(aldi.categories.flatMap(\.items).map(\.id), ["a", "b"])
        XCTAssertEqual(noShop.categories.flatMap(\.items).map(\.id), ["c"])
    }

    func testActiveSectionsExcludePickedUpItems() async throws {
        let vm = buildViewModel()
        var a = item("a"), b = item("b", isPickedUp: true)
        a.shop = "Aldi"
        b.shop = "Aldi"
        await emit([a, b], to: vm)

        let aldi = try XCTUnwrap(vm.activeGroups.first { $0.shop == "Aldi" })
        XCTAssertEqual(aldi.categories.flatMap(\.items).map(\.id), ["a"])
    }

    func testActiveSectionsSortCategoriesAlphabeticallyWithUncategorizedLast() async throws {
        let vm = buildViewModel()
        var a = item("a"), b = item("b"), c = item("c")
        a.shop = "Aldi"
        a.categoryName = "Snacks"
        b.shop = "Aldi"
        b.categoryName = "Bakery"
        c.shop = "Aldi"
        c.categoryName = nil
        await emit([a, b, c], to: vm)

        let aldi = try XCTUnwrap(vm.activeGroups.first { $0.shop == "Aldi" })
        // Bakery before Snacks (alphabetical); the uncategorized bucket (nil) last.
        XCTAssertEqual(aldi.categories.map(\.name), ["Bakery", "Snacks", nil])
        XCTAssertEqual(aldi.categories.last?.items.map(\.id), ["c"])
    }

    // Android reads these from SavedStateHandle; iOS passes them to the screen's models.
    func testListIdAndListNameComeFromTheScreen() {
        let vm = ListDetailViewModel(listId: "L1", source: source, haptics: haptics)
        let model = chrome(.unauthenticated)

        XCTAssertEqual(vm.listId, "L1")
        XCTAssertEqual(model.listName, "Groceries")
    }

    // iOS has no optional navigation keys: an empty id and name are kept as given, not replaced.
    func testMissingListIdAndNameStayEmptyStrings() {
        let vm = ListDetailViewModel(listId: "", source: source, haptics: haptics)
        let model = ListDetailChromeModel(listName: "", authState: { .unauthenticated }, haptics: haptics)

        XCTAssertEqual(vm.listId, "")
        XCTAssertEqual(model.listName, "")
    }

    // MARK: Share as text (ListDetailChromeModel)

    func testShareOnAnUnlockedListEmitsTheFormattedText() async throws {
        let vm = buildViewModel()
        let model = chrome(.unauthenticated, items: { vm.items })
        await emit([item("a", name: "Milk")], to: vm)

        model.perform(.shareAsText)

        let text = try XCTUnwrap(model.sharedText)
        XCTAssertTrue(text.contains("Groceries"))
        XCTAssertTrue(text.contains("Milk"))
    }

    // MARK: Dialog state
    //
    // iOS keeps which sheet is up in the screen's SwiftUI state; these cover what the
    // models own: the add sheet starts blank and the edit sheet starts from the item.

    func testAddDialogOpensBlankAndDismissingItSavesNothing() async {
        let vm = buildViewModel()
        let opened = ItemDraft()

        XCTAssertEqual(opened.name, "")
        XCTAssertEqual(opened.quantity, "")
        XCTAssertNil(opened.categoryId)
        XCTAssertFalse(opened.isValid)
        let saved = await vm.add(opened)
        XCTAssertFalse(saved)
        XCTAssertTrue(source.added.isEmpty)
    }

    func testEditPrefillsTheDraftFromTheItem() {
        let item = ShoppingItem(id: "i1", name: "Milk", quantity: "2", categoryId: "cat-dairy-eggs",
                                shop: "Aldi", note: "semi")
        let draft = ItemDraft(editing: item)
        XCTAssertEqual(draft.name, "Milk")
        XCTAssertEqual(draft.quantity, "2")
        XCTAssertEqual(draft.categoryId, "cat-dairy-eggs")
        XCTAssertEqual(draft.shop, "Aldi")
        XCTAssertEqual(draft.note, "semi")
    }

    // MARK: addItem / togglePickedUp / addCategory

    func testAddItemSuccessClosesTheSheet() async {
        let vm = buildViewModel()

        let saved = await vm.add(ItemDraft(name: "Milk", quantity: "2 L", categoryId: "cat-dairy-eggs"))

        XCTAssertTrue(saved)
        XCTAssertEqual(source.added.count, 1)
        XCTAssertEqual(source.added.first?.name, "Milk")
        XCTAssertEqual(source.added.first?.quantity, "2 L")
        XCTAssertEqual(source.added.first?.categoryId, "cat-dairy-eggs")
        XCTAssertNil(vm.errorMessage)
    }

    func testAddItemFailureSurfacesTheErrorAndKeepsTheSheetOpen() async {
        source.addResult = .failure(.validation("Item name can't be empty."))
        let vm = buildViewModel()

        let saved = await vm.add(ItemDraft(name: "Milk", quantity: "1"))

        XCTAssertFalse(saved)
        XCTAssertEqual(vm.errorMessage, "Item name can't be empty.")
    }

    func testTogglePickedUpDelegatesToTheRepository() async {
        let vm = buildViewModel()
        await emit([item("1"), item("2", isPickedUp: true)], to: vm)

        await vm.toggle("1")
        await vm.toggle("2")

        XCTAssertEqual(source.toggled.map(\.itemId), ["1", "2"])
        XCTAssertEqual(source.toggled.map(\.isPickedUp), [true, false])
    }

    func testTogglePickedUpFailureSurfacesTheError() async {
        source.toggleResult = .failure(.database("toggle failed"))
        let vm = buildViewModel()
        await emit([item("1")], to: vm)

        await vm.toggle("1")

        XCTAssertEqual(vm.errorMessage, "toggle failed")
    }

    // The new category is built locally from the name passed in, not read back from storage,
    // and selected so the item saves with it.
    func testAddCategoryHandsTheNewCategoryOn() async {
        let categories = FakeCategoryPickerSource(addResult: .success("cat-1"))
        let picker = CategoryPickerModel(categories: [], source: categories)
        picker.selectOther()
        picker.newCategoryName = "Dairy"

        let result = await picker.resolveCategoryId()

        XCTAssertEqual(result, .success("cat-1"))
        XCTAssertEqual(categories.added, ["Dairy"])
        XCTAssertEqual(picker.selection, .category("cat-1"))
        XCTAssertEqual(picker.searchText, "Dairy")
    }

    func testAddCategoryFailureSurfacesTheErrorAndSkipsTheItem() async {
        let categories = FakeCategoryPickerSource(addResult: .failure(.database()))
        let picker = CategoryPickerModel(categories: [], source: categories)
        picker.selectOther()
        picker.newCategoryName = "Dairy"
        let vm = buildViewModel()

        let saved = await vm.add(ItemDraft(name: "Milk", quantity: "1"), picker: picker)

        XCTAssertFalse(saved)
        XCTAssertEqual(vm.errorMessage, AppError.database().message)
        XCTAssertTrue(source.added.isEmpty)
        XCTAssertEqual(picker.selection, .other)
    }

    // MARK: Voice

    // The detail screen's voice delegate is `saveVoiceDrafts(_:intoList:using:)` (the screen
    // passes its list id and the list repository).
    func testAddItemsWithVoiceDelegatesAndReturnsTheResultUnchanged() async {
        let repository = RecordingListItemsAdder(result: .success("L1"))
        let drafts = [TestData.draft(name: "Milk")]

        let result = await saveVoiceDrafts(drafts, intoList: "L1", using: repository)

        XCTAssertEqual(result, .success("L1"))
        XCTAssertEqual(repository.calls.map(\.listId), ["L1"])
        XCTAssertEqual(repository.calls.map(\.drafts), [drafts])
    }

    // MARK: Teardown (Android onCleared, ListLeaveGuard)

    // Leaving a list with nothing in it cleans the list up.
    func testTeardownDeletesAListLeftEmpty() async {
        await leaveGuard.tearDown().value

        XCTAssertEqual(["L1"], cleaner.deleteCalls)
    }

    // The dangerous interleaving: Undo is tapped and the user backs out in the same
    // breath. The teardown waits for the restore BEFORE asking whether the list is
    // empty; without that the check races the restore, sees zero items, and deletes
    // the very list the user just rescued.
    func testTeardownWaitsForAnInFlightUndoBeforeDecidingTheListIsEmpty() async {
        let model = await loadedForLeaving(items: [TestData.storedItem("a")])
        await model.delete("a")
        let (gate, release) = AsyncStream<Void>.makeStream()

        leaveGuard.trackUndo { [model] in
            for await _ in gate { break }
            await model.undoDelete()
        }
        let teardown = leaveGuard.tearDown()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(cleaner.deleteCalls.isEmpty, "the restore is still parked, so no emptiness check yet")

        release.yield()
        await teardown.value

        XCTAssertEqual(1, source.restored.count)
        XCTAssertEqual(["L1"], cleaner.deleteCalls)
    }

    func testTeardownProceedsImmediatelyWhenNoUndoIsInFlight() async {
        await leaveGuard.tearDown().value

        XCTAssertEqual(1, cleaner.deleteCalls.count)
    }
}
