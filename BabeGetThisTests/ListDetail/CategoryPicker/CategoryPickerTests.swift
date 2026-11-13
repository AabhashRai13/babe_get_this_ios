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
