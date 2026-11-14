import XCTest
@testable import BabeGetThis

/// List detail view model cases beyond the direct ports of Android's ShoppingItemsViewModelTest
/// (those are in `ShoppingItemsViewModelTests`): list-completed against a fake repository,
/// the undo snackbar, and database-backed cases that run the real `ShoppingItemRepository`
/// on an in-memory database.
@MainActor
final class ListDetailViewModelTests: XCTestCase {
    private var source: FakeListDetailItemsSource!
    private var haptics: RecordingHapticPlayer!
    private var observation: Task<Void, Never>?

    override func setUp() async throws {
        source = FakeListDetailItemsSource()
        haptics = RecordingHapticPlayer()
    }

    override func tearDown() async throws {
        observation?.cancel()
        observation = nil
    }

    /// Android's `buildViewModel()`: the view model starts collecting straight away.
    private func buildViewModel(listId: String = "L1", source: (any ListDetailItemsSource)? = nil) -> ListDetailViewModel {
        let fake: any ListDetailItemsSource = self.source
        let vm = ListDetailViewModel(listId: listId, source: source ?? fake, haptics: haptics)
        observation = Task { await vm.observeItems() }
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

    // MARK: Database

    /// A real repository over an in-memory database, with one guest list "list-1".
    private func databaseRepository() async throws -> (AppDatabase, ShoppingItemRepository) {
        let db = try AppDatabase.inMemory()
        try await db.lists.insertList(TestData.listEntity(id: "list-1"))
        let repository = ShoppingItemRepository(
            itemDao: db.items, categoryDao: db.categories, listDao: db.lists,
            syncKicker: CountingSyncKicker(), safeCall: SafeCall(reporter: SilentAppErrorReporter()))
        return (db, repository)
    }

    func testItemsAreObservedLiveFromTheDatabase() async throws {
        let (db, repository) = try await databaseRepository()
        try await db.items.insertItem(TestData.itemEntity(id: "a", name: "Milk", categoryId: "cat-dairy-eggs"))
        let vm = buildViewModel(listId: "list-1", source: repository)

        await listDetailEventually { vm.items.map(\.name) == ["Milk"] }
        XCTAssertTrue(vm.hasLoaded)
        XCTAssertEqual(vm.items.first?.categoryName, "Dairy & Eggs")

        // A row written straight to the database (as sync would) shows up without a reload.
        try await db.items.insertItem(TestData.itemEntity(id: "b", name: "Bread", shop: "Aldi"))
        await listDetailEventually { vm.totalCount == 2 }
        XCTAssertEqual(vm.activeGroups.map(\.shop), ["Aldi", nil])

        // Ticking goes through the repository, and the database change comes back live.
        await vm.toggle("a")
        await listDetailEventually { vm.completedItems.map(\.id) == ["a"] }
        let ticked = try await db.items.itemRaw(id: "a")
        XCTAssertEqual(ticked?.isPickedUp, true)

        // Items of other lists never appear.
        try await db.lists.insertList(TestData.listEntity(id: "list-2"))
        try await db.items.insertItem(TestData.itemEntity(id: "c", listId: "list-2", name: "Eggs"))
        try await db.items.insertItem(TestData.itemEntity(id: "d", name: "Jam"))
        await listDetailEventually { vm.totalCount == 3 }
        XCTAssertFalse(vm.items.contains { $0.id == "c" })
    }

    func testSampleListHasFixedItems() async throws {
        let db = try AppDatabase.inMemory()
        try SampleListSeeder.seed(db)
        let repository = ShoppingItemRepository(
            itemDao: db.items, categoryDao: db.categories, listDao: db.lists,
            syncKicker: NoOpSyncKicker(), safeCall: SafeCall(reporter: SilentAppErrorReporter()))
        let vm = buildViewModel(listId: ShoppingItem.sundayRoastListId, source: repository)

        await listDetailEventually { vm.totalCount == 5 }
        XCTAssertEqual(vm.activeItems.map(\.name), ["Red wine", "Lamb leg", "Double cream", "Baby potatoes"])
        XCTAssertEqual(vm.completedItems.map(\.name), ["Sourdough"])
        XCTAssertEqual(vm.activeItems[1].quantity, "2.5 kg")
        XCTAssertEqual(vm.activeItems[1].shop, "The Butcher Block")
        XCTAssertEqual(vm.activeItems[0].note, "Something that goes with lamb")
        XCTAssertEqual(vm.pickedUpCount, 1)
        XCTAssertEqual(vm.percent, 20)
        XCTAssertEqual(vm.progress, 0.2, accuracy: 0.0001)
    }

    func testAddThroughTheRepositoryRequiresNameAndQuantity() async throws {
        let (db, repository) = try await databaseRepository()
        let vm = buildViewModel(listId: "list-1", source: repository)
        await listDetailEventually { vm.hasLoaded }

        let rejected1 = await vm.add(ItemDraft(name: "Bread", quantity: ""))
        let rejected2 = await vm.add(ItemDraft(name: "   ", quantity: "1"))
        let rejected3 = await vm.add(ItemDraft(name: "", quantity: "1"))
        XCTAssertFalse(rejected1 || rejected2 || rejected3)
        let none = try await db.items.itemsByListId("list-1")
        XCTAssertTrue(none.isEmpty)

        let added = await vm.add(ItemDraft(name: " Bread ", quantity: "2", categoryId: "cat-bakery-bread",
                                           shop: " Aldi ", note: "  "))
        XCTAssertTrue(added)
        await listDetailEventually { vm.totalCount == 1 }
        XCTAssertEqual(vm.items[0].name, "Bread")
        XCTAssertEqual(vm.items[0].shop, "Aldi")
        XCTAssertNil(vm.items[0].note)
        XCTAssertFalse(vm.items[0].isPickedUp)
        XCTAssertEqual(vm.items[0].categoryId, "cat-bakery-bread")
        XCTAssertEqual(vm.items[0].categoryName, "Bakery & Bread")
    }

    func testDeleteThenUndoRestoresTheItemInTheDatabase() async throws {
        let (db, repository) = try await databaseRepository()
        try await db.items.insertItem(TestData.itemEntity(id: "a", name: "Milk"))
        try await db.items.insertItem(TestData.itemEntity(id: "b", name: "Bread"))
        let vm = buildViewModel(listId: "list-1", source: repository)
        await listDetailEventually { vm.totalCount == 2 }
        let before = vm.items

        await vm.delete("a")
        await listDetailEventually { vm.totalCount == 1 }
        XCTAssertEqual(vm.undoMessage, "Milk deleted")

        await vm.undoDelete()
        await listDetailEventually { vm.totalCount == 2 }
        XCTAssertEqual(vm.sortedItems, before.sorted { $0.name < $1.name })
        XCTAssertNil(vm.pendingUndo)
        XCTAssertNil(vm.undoMessage)
    }

    func testEmptyListShowsTheFirstItemPrompt() async throws {
        let (db, repository) = try await databaseRepository()
        try await db.items.insertItem(TestData.itemEntity(id: "x"))
        let vm = buildViewModel(listId: "list-1", source: repository)
        await listDetailEventually { vm.totalCount == 1 }
        XCTAssertFalse(vm.isEmpty)

        await vm.delete("x")
        await listDetailEventually { vm.isEmpty }
    }

    // MARK: ListJustCompleted transition logic

    func testEmitsListJustCompletedWhenLastUncheckedItemIsTickedOff() async {
        let vm = buildViewModel()

        // Start with two unchecked items: not all done.
        await emit([item("1"), item("2")], to: vm)
        XCTAssertEqual(vm.completionCount, 0)

        // Flip both to picked up: the transition fires.
        await emit([item("1", isPickedUp: true), item("2", isPickedUp: true)], to: vm)
        XCTAssertEqual(vm.completionCount, 1)
        XCTAssertEqual(haptics.played, [.success])
    }

    func testDoesNotEmitListJustCompletedOnInitialLoadOfAlreadyCompleteList() async {
        // Pre-seeded before the view model subscribes: opening a finished list must not buzz.
        let complete = [item("1", isPickedUp: true), item("2", isPickedUp: true)]
        source.send(complete)

        let vm = buildViewModel()
        await listDetailEventually { vm.storedItems == complete }

        XCTAssertTrue(vm.isAllDone)
        XCTAssertEqual(vm.completionCount, 0)
        XCTAssertTrue(haptics.played.isEmpty)
    }

    func testEmitsListJustCompletedOnTheSecondCompletionWhenUncheckThenRecomplete() async {
        let vm = buildViewModel()

        // First completion.
        await emit([item("1")], to: vm)
        await emit([item("1", isPickedUp: true)], to: vm)
        XCTAssertEqual(vm.completionCount, 1)

        // Uncheck, then re-complete: the second transition fires too.
        await emit([item("1", isPickedUp: false)], to: vm)
        await emit([item("1", isPickedUp: true)], to: vm)
        XCTAssertEqual(vm.completionCount, 2)
        XCTAssertEqual(haptics.played, [.success, .success])
    }

    // Product rule: nine of ten ticked and the tenth no longer needed, so it is deleted.
    // The trip is done, and that counts as completing the list.
    func testDeletingTheLastUntickedItemCompletesTheList() async {
        let vm = buildViewModel()

        await emit([item("1", isPickedUp: true), item("2")], to: vm)
        await emit([item("1", isPickedUp: true)], to: vm)

        XCTAssertEqual(vm.completionCount, 1)
    }

    func testEmptyListNeverTriggersListJustCompleted() async {
        let vm = buildViewModel()

        // An empty list isn't "all done": it must be non-empty AND all picked up.
        await emit([], to: vm)
        await emit([], to: vm)

        XCTAssertFalse(vm.isAllDone)
        XCTAssertEqual(vm.percent, 0)
        XCTAssertEqual(vm.completionCount, 0)
        XCTAssertTrue(haptics.played.isEmpty)
    }

    // MARK: Delete + Undo

    func testDismissUndoMakesDeleteFinal() async {
        let vm = buildViewModel()
        await emit([item("1", name: "Red wine")], to: vm)
        await vm.delete("1")

        vm.dismissUndo()
        await vm.undoDelete()

        XCTAssertNil(vm.undoMessage)
        XCTAssertTrue(source.restored.isEmpty)
    }

    func testUndoSnackbarCopyAndDurationMatchAndroid() async {
        let vm = buildViewModel()
        await emit([item("1", name: "Red wine")], to: vm)
        XCTAssertNil(vm.undoMessage)

        await vm.delete("1")

        XCTAssertEqual(vm.undoMessage, "Red wine deleted")
        XCTAssertEqual(ListDetailViewModel.undoSnackbarDuration, .seconds(4))
    }

    // MARK: uiState

    func testNothingIsShownBeforeTheItemsHaveLoaded() {
        let vm = ListDetailViewModel(listId: "L1", source: source, haptics: haptics)
        XCTAssertFalse(vm.hasLoaded)
    }
}

/// Grouping and ordering of the derived screen state (Android `buildActiveSections` and the
/// DAO sort), kept from the in-memory model's tests.
final class ListDetailContentTests: XCTestCase {
    private func content(_ items: [ShoppingItem]) -> ListDetailContent {
        ListDetailContent(items: items)
    }

    func testGroupingByShopThenCategory() {
        let groups = content(ShoppingItem.sundayRoast).activeGroups
        XCTAssertEqual(groups.map(\.shop), ["Dan Murphys", "The Butcher Block", "Woolworths"])
        let woolworths = groups[2]
        XCTAssertEqual(woolworths.categories.map(\.name), ["Dairy & Eggs", "Fruits & Vegetables"])
        XCTAssertEqual(woolworths.categories[0].items.map(\.name), ["Double cream"])
    }

    func testItemsWithoutShopOrCategoryGroupLast() {
        let state = content([
            ShoppingItem(id: "a", name: "Soap", quantity: "1"),
            ShoppingItem(id: "b", name: "Milk", quantity: "2 L", categoryId: nil, shop: "Aldi"),
            ShoppingItem(id: "c", name: "Eggs", quantity: "12", categoryId: "cat-dairy-eggs", shop: "Aldi"),
        ])
        XCTAssertEqual(state.activeGroups.map(\.shop), ["Aldi", nil])
        XCTAssertEqual(state.activeGroups[0].categories.map(\.name), ["Dairy & Eggs", nil])
    }

    // Android sorts in SQL (shop, categoryId, name), so items inside one category and
    // the COMPLETED section come out by name, not by insertion order.
    func testItemsInOneCategorySortByName() {
        let state = content([
            ShoppingItem(id: "b", name: "Bananas", quantity: "6", categoryId: "cat-fruits-vegetables", shop: "Aldi"),
            ShoppingItem(id: "a", name: "Apples", quantity: "4", categoryId: "cat-fruits-vegetables", shop: "Aldi"),
            ShoppingItem(id: "z", name: "Zucchini", quantity: "1", isPickedUp: true),
            ShoppingItem(id: "y", name: "Yoghurt", quantity: "1", categoryId: "cat-dairy-eggs", isPickedUp: true),
            ShoppingItem(id: "c", name: "Carrots", quantity: "1", isPickedUp: true),
        ])
        XCTAssertEqual(state.activeGroups[0].categories[0].items.map(\.name), ["Apples", "Bananas"])
        // No shop for all three; the categorised one first, then by name.
        XCTAssertEqual(state.completedItems.map(\.name), ["Yoghurt", "Carrots", "Zucchini"])
    }

    func testShopsSortWithNoShopLastAndCategoriesByName() {
        let state = content([
            ShoppingItem(id: "1", name: "Soap", quantity: "1", categoryId: "cat-household-cleaning"),
            ShoppingItem(id: "2", name: "Steak", quantity: "1", categoryId: "cat-meat-seafood", shop: "Costco"),
            ShoppingItem(id: "3", name: "Milk", quantity: "1", categoryId: "cat-dairy-eggs", shop: "Costco"),
            ShoppingItem(id: "4", name: "Tape", quantity: "1", shop: "Bunnings"),
        ])
        XCTAssertEqual(state.activeGroups.map(\.shop), ["Bunnings", "Costco", nil])
        XCTAssertEqual(state.activeGroups[1].categories.map(\.name), ["Dairy & Eggs", "Meat & Seafood"])
    }

    func testActiveSectionsExcludePickedUpItems() {
        let state = content([
            ShoppingItem(id: "1", name: "Soap", quantity: "1", shop: "Aldi", isPickedUp: true),
            ShoppingItem(id: "2", name: "Milk", quantity: "1", shop: "Coles"),
        ])
        XCTAssertEqual(state.activeGroups.map(\.shop), ["Coles"])
    }

    func testNoShopGroupIsHeadedGeneralOnlyWhenOtherShopsExist() throws {
        let mixed = content([
            ShoppingItem(id: "1", name: "Soap", quantity: "1"),
            ShoppingItem(id: "2", name: "Milk", quantity: "1", shop: "Aldi"),
        ])
        let general = try XCTUnwrap(mixed.activeGroups.last)
        XCTAssertNil(general.shop)
        XCTAssertEqual(general.title, "General")
        XCTAssertTrue(mixed.showsShopHeader(general))

        let noShops = content([ShoppingItem(id: "1", name: "Soap", quantity: "1")])
        XCTAssertEqual(noShops.activeGroups.count, 1)
        XCTAssertFalse(noShops.showsShopHeader(noShops.activeGroups[0]))
    }

    func testCategoryHeadersHiddenWhenTheOnlyBucketIsUncategorized() {
        let state = content([
            ShoppingItem(id: "1", name: "Soap", quantity: "1", shop: "Aldi"),
            ShoppingItem(id: "2", name: "Milk", quantity: "1", categoryId: "cat-dairy-eggs", shop: "Coles"),
            ShoppingItem(id: "3", name: "Tape", quantity: "1", shop: "Coles"),
        ])
        let aldi = state.activeGroups[0]
        let coles = state.activeGroups[1]
        XCTAssertTrue(aldi.hidesCategoryHeaders)
        XCTAssertFalse(coles.hidesCategoryHeaders)
        XCTAssertEqual(coles.categories.map(\.title), ["Dairy & Eggs", "Uncategorized"])
    }

    func testUnknownCategoryIdIsUncategorized() {
        let state = content([ShoppingItem(id: "1", name: "Thing", quantity: "1", categoryId: "cat-gone")])
        XCTAssertNil(state.items[0].categoryName)
        XCTAssertEqual(state.activeGroups[0].categories.map(\.name), [nil])
    }

    /// The repository resolves names from the categories table, so a custom category shows its name.
    func testStoredCategoryNameIsUsed() {
        let stored = StoredShoppingItem(id: "1", listId: "L1", name: "Kibble", quantity: "1", categoryId: "custom-1",
                                        categoryName: "Dog stuff", createdAt: 0, updatedAt: 0)
        XCTAssertEqual(ShoppingItem(stored).categoryName, "Dog stuff")
    }

    func testCategoryPickerUsesTheDefaultCategoriesByName() {
        let names = DefaultCategories.sortedByName.map(\.name)
        XCTAssertEqual(names.count, 48)
        XCTAssertEqual(names, names.sorted())
        XCTAssertEqual(names.first, "Accessories & Jewelry")
        XCTAssertEqual(DefaultCategories.name(for: "cat-dairy-eggs"), "Dairy & Eggs")
    }
}
