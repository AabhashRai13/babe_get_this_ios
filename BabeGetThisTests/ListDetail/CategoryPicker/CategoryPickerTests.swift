import XCTest
@testable import BabeGetThis

/// Category picker in the add/edit item sheet (Android `AddItemDialog` category dropdown; DET-08, STR-06).
@MainActor
final class CategoryPickerTests: XCTestCase {
    private func picker(source: (any CategoryPickerSource)? = nil) -> CategoryPickerModel {
        CategoryPickerModel(
            categories: [
                ProductCategory(id: "c1", name: "Dairy & Eggs", isDefault: true),
                ProductCategory(id: "c2", name: "Snacks", isDefault: true),
                ProductCategory(id: "c3", name: "Frozen Foods", isDefault: true)
            ],
            source: source)
    }

    func testCategoryFilterIsCaseInsensitive() {
        let model = picker()

        model.searchChanged("dAiRy")
        XCTAssertEqual(model.filteredCategories.map(\.id), ["c1"])

        model.searchChanged("FOODS")
        XCTAssertEqual(model.filteredCategories.map(\.id), ["c3"])

        model.searchChanged("   ")
        XCTAssertEqual(model.filteredCategories.count, 3, "a blank search shows everything")
    }

    func testNoMatchShowsMessage() {
        let model = picker()

        model.searchChanged("zzz")

        XCTAssertTrue(model.filteredCategories.isEmpty)
        XCTAssertEqual(model.noMatchMessage, "No categories match \"zzz\"")

        model.searchChanged("")
        XCTAssertNil(model.noMatchMessage, "no message while the search is blank")
        model.searchChanged("snack")
        XCTAssertNil(model.noMatchMessage)
    }

    func testOtherCreatesCategoryAndSavesItemWithIt() async throws {
        let db = try AppDatabase.inMemory()
        let repository = CategoryRepository(dao: db.categories, safeCall: SafeCall(reporter: SilentAppErrorReporter()))
        let items = FakeListDetailItemsSource()
        let vm = ListDetailViewModel(listId: "L1", source: items, haptics: RecordingHapticPlayer())
        let model = picker(source: repository)

        model.selectOther()
        XCTAssertTrue(model.isCreatingNewCategory)
        model.newCategoryName = "  Pet supplies  "
        var draft = ItemDraft()
        draft.name = "Dog food"
        draft.quantity = "2"

        let saved = await vm.add(draft, picker: model)

        XCTAssertTrue(saved)
        let created = try await db.categories.allCategories().first { $0.name == "Pet supplies" }
        let category = try XCTUnwrap(created, "Other creates the category, trimmed")
        XCTAssertFalse(category.isDefault)
        XCTAssertEqual(items.added.count, 1)
        XCTAssertEqual(items.added.first?.categoryId, category.id)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Live categories (Android `categoryRepository.getAllCategories()`)

    private func categoryRepository() throws -> (AppDatabase, CategoryRepository) {
        let db = try AppDatabase.inMemory()
        return (db, CategoryRepository(dao: db.categories, safeCall: SafeCall(reporter: SilentAppErrorReporter())))
    }

    private func draft(_ name: String) -> ItemDraft {
        var draft = ItemDraft()
        draft.name = name
        draft.quantity = "1"
        return draft
    }

    func testThePickerListsCustomCategoriesLive() async throws {
        let (_, repository) = try categoryRepository()
        let model = CategoryPickerModel(source: repository)
        let observing = Task { await model.observeCategories() }
        defer { observing.cancel() }

        _ = try await repository.addCategory(name: "Camping gear")

        await listDetailEventually("the custom category is offered") {
            model.categories.contains { $0.name == "Camping gear" }
        }
        let names = model.categories.map(\.name)
        XCTAssertEqual(names, names.sorted(), "A→Z, the DAO's order")
        XCTAssertTrue(model.categories.contains { $0.isDefault }, "the defaults stay")
    }

    // A category made through "Other" is offered when the sheet opens again, and an item
    // saved with it opens in edit mode with that category selected.
    func testACategoryCreatedThroughOtherIsListedAndPreselectedWhenEditing() async throws {
        let (_, repository) = try categoryRepository()
        let items = FakeListDetailItemsSource()
        let vm = ListDetailViewModel(listId: "L1", source: items, haptics: RecordingHapticPlayer())
        let first = CategoryPickerModel(source: repository)
        first.selectOther()
        first.newCategoryName = "Camping gear"
        let saved = await vm.add(draft("Tent pegs"), picker: first)
        XCTAssertTrue(saved)
        let categoryId = try XCTUnwrap(items.added.first?.categoryId)

        let reopened = CategoryPickerModel(selectedId: categoryId, source: repository)
        let observing = Task { await reopened.observeCategories() }
        defer { observing.cancel() }

        await listDetailEventually("the edited item's custom category is shown") {
            reopened.searchText == "Camping gear"
        }
        XCTAssertEqual(reopened.selectedCategoryId, categoryId)
        XCTAssertTrue(reopened.categories.contains { $0.id == categoryId && $0.name == "Camping gear" })
    }

    func testOtherWithAnExistingNameReusesThatCategory() async throws {
        let (db, repository) = try categoryRepository()
        let existingId = try await repository.addCategory(name: "Camping gear").get()
        let items = FakeListDetailItemsSource()
        let vm = ListDetailViewModel(listId: "L1", source: items, haptics: RecordingHapticPlayer())
        let model = CategoryPickerModel(source: repository)
        let observing = Task { await model.observeCategories() }
        defer { observing.cancel() }
        await listDetailEventually { model.categories.contains { $0.id == existingId } }

        model.selectOther()
        model.newCategoryName = "  camping GEAR "
        let saved = await vm.add(draft("Tent pegs"), picker: model)

        XCTAssertTrue(saved)
        XCTAssertEqual(items.added.first?.categoryId, existingId)
        let named = try await db.categories.allCategories().filter { $0.name.lowercased() == "camping gear" }
        XCTAssertEqual(named.count, 1, "no duplicate row")
    }

    func testOtherWithADefaultsNameReusesTheDefault() async throws {
        let (db, repository) = try categoryRepository()
        let before = try await db.categories.allCategories().count
        let dairy = try XCTUnwrap(DefaultCategories.sortedByName.first { $0.name == "Dairy & Eggs" })
        let items = FakeListDetailItemsSource()
        let vm = ListDetailViewModel(listId: "L1", source: items, haptics: RecordingHapticPlayer())
        let model = CategoryPickerModel(source: repository)
        model.selectOther()
        model.newCategoryName = "dairy & eggs"

        let saved = await vm.add(draft("Milk"), picker: model)

        XCTAssertTrue(saved)
        XCTAssertEqual(items.added.first?.categoryId, dairy.id)
        let after = try await db.categories.allCategories().count
        XCTAssertEqual(after, before)
    }

    // The sheet stays open when the save fails; tapping Add again must not create the
    // category a second time.
    func testARetryAfterAFailedSaveReusesTheCreatedCategory() async throws {
        let (db, repository) = try categoryRepository()
        let items = FakeListDetailItemsSource()
        items.addResult = .failure(.database())
        let vm = ListDetailViewModel(listId: "L1", source: items, haptics: RecordingHapticPlayer())
        let model = picker(source: repository)
        model.selectOther()
        model.newCategoryName = "Camping gear"

        let failed = await vm.add(draft("Tent pegs"), picker: model)
        XCTAssertFalse(failed)
        items.addResult = .success("new-id")
        let saved = await vm.add(draft("Tent pegs"), picker: model)

        XCTAssertTrue(saved)
        let created = try await db.categories.allCategories().filter { $0.name == "Camping gear" }
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(items.added.map(\.categoryId), [created.first?.id, created.first?.id])
        XCTAssertEqual(model.selection, .category(try XCTUnwrap(created.first?.id)))
    }

    func testNoneSavesItemWithoutCategory() async {
        let items = FakeListDetailItemsSource()
        let vm = ListDetailViewModel(listId: "L1", source: items, haptics: RecordingHapticPlayer())
        let model = picker()
        model.select(ProductCategory(id: "c2", name: "Snacks", isDefault: true))
        model.selectNone()
        var draft = ItemDraft()
        draft.name = "Chips"
        draft.quantity = "1"

        let saved = await vm.add(draft, picker: model)

        XCTAssertTrue(saved)
        XCTAssertNil(items.added.first?.categoryId)
    }
}
