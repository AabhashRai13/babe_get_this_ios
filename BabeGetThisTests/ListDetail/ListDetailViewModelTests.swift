import XCTest
@testable import BabeGetThis

@MainActor
final class ListDetailViewModelTests: XCTestCase {
    func testSampleListHasFixedItems() {
        let vm = ListDetailViewModel(listId: "sample-sunday-roast")
        XCTAssertEqual(vm.activeItems.map(\.name), ["Red wine", "Lamb leg", "Double cream", "Baby potatoes"])
        XCTAssertEqual(vm.completedItems.map(\.name), ["Sourdough"])
        XCTAssertEqual(vm.activeItems[1].quantity, "2.5 kg")
        XCTAssertEqual(vm.activeItems[1].shop, "The Butcher Block")
        XCTAssertEqual(vm.activeItems[0].note, "Something that goes with lamb")
    }

    func testOtherListsStartEmpty() {
        let vm = ListDetailViewModel(listId: "sample-bbq")
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.percent, 0)
        XCTAssertFalse(vm.isAllDone)
    }

    func testGroupingByShopThenCategory() {
        let vm = ListDetailViewModel(listId: "sample-sunday-roast")
        let groups = vm.activeGroups
        XCTAssertEqual(groups.map(\.shop), ["Dan Murphys", "The Butcher Block", "Woolworths"])
        let woolworths = groups[2]
        XCTAssertEqual(woolworths.categories.map(\.name), ["Dairy & Eggs", "Fruits & Vegetables"])
        XCTAssertEqual(woolworths.categories[0].items.map(\.name), ["Double cream"])
    }

    func testItemsWithoutShopOrCategoryGroupLast() {
        let vm = ListDetailViewModel(items: [
            ShoppingItem(id: "a", name: "Soap", quantity: "1"),
            ShoppingItem(id: "b", name: "Milk", quantity: "2 L", categoryId: nil, shop: "Aldi"),
            ShoppingItem(id: "c", name: "Eggs", quantity: "12", categoryId: "cat-dairy-eggs", shop: "Aldi"),
        ])
        XCTAssertEqual(vm.activeGroups.map(\.shop), ["Aldi", nil])
        XCTAssertEqual(vm.activeGroups[0].categories.map(\.name), ["Dairy & Eggs", nil])
    }

    func testProgressCountsAndPercent() {
        let vm = ListDetailViewModel(listId: "sample-sunday-roast")
        XCTAssertEqual(vm.totalCount, 5)
        XCTAssertEqual(vm.pickedUpCount, 1)
        XCTAssertEqual(vm.percent, 20)
        XCTAssertEqual(vm.progress, 0.2, accuracy: 0.0001)
        let third = ListDetailViewModel(items: [
            ShoppingItem(name: "a", quantity: "1", isPickedUp: true),
            ShoppingItem(name: "b", quantity: "1"),
            ShoppingItem(name: "c", quantity: "1"),
        ])
        XCTAssertEqual(third.percent, 33)
    }

    func testToggleMovesItemBetweenActiveAndCompleted() {
        let vm = ListDetailViewModel(listId: "sample-sunday-roast")
        vm.toggle("sr-lamb-leg")
        XCTAssertFalse(vm.activeItems.contains { $0.id == "sr-lamb-leg" })
        XCTAssertTrue(vm.completedItems.contains { $0.id == "sr-lamb-leg" })
        XCTAssertEqual(vm.pickedUpCount, 2)
        vm.toggle("sr-lamb-leg")
        XCTAssertTrue(vm.activeItems.contains { $0.id == "sr-lamb-leg" })
    }

    func testAllDoneWhenEveryItemTicked() {
        let vm = ListDetailViewModel(items: [ShoppingItem(id: "x", name: "a", quantity: "1")])
        XCTAssertFalse(vm.isAllDone)
        vm.toggle("x")
        XCTAssertTrue(vm.isAllDone)
        XCTAssertEqual(vm.percent, 100)
    }

    func testDeleteThenUndoRestoresPosition() {
        let vm = ListDetailViewModel(listId: "sample-sunday-roast")
        let before = vm.items
        vm.delete("sr-double-cream")
        XCTAssertEqual(vm.totalCount, 4)
        XCTAssertEqual(vm.pendingUndo?.item.name, "Double cream")
        vm.undoDelete()
        XCTAssertEqual(vm.items, before)
        XCTAssertNil(vm.pendingUndo)
    }

    func testDismissUndoMakesDeleteFinal() {
        let vm = ListDetailViewModel(listId: "sample-sunday-roast")
        vm.delete("sr-red-wine")
        vm.dismissUndo()
        vm.undoDelete()
        XCTAssertFalse(vm.items.contains { $0.id == "sr-red-wine" })
    }

    func testAddRequiresNameAndQuantity() {
        let vm = ListDetailViewModel(items: [])
        XCTAssertFalse(vm.add(ItemDraft(name: "Bread", quantity: "")))
        XCTAssertFalse(vm.add(ItemDraft(name: "   ", quantity: "1")))
        XCTAssertFalse(vm.add(ItemDraft(name: "", quantity: "1")))
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertTrue(vm.add(ItemDraft(name: " Bread ", quantity: "2", categoryId: "cat-bakery-bread", shop: " Aldi ", note: "  ")))
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items[0].name, "Bread")
        XCTAssertEqual(vm.items[0].shop, "Aldi")
        XCTAssertNil(vm.items[0].note)
        XCTAssertFalse(vm.items[0].isPickedUp)
        XCTAssertEqual(vm.items[0].categoryId, "cat-bakery-bread")
        XCTAssertEqual(vm.items[0].categoryName, "Bakery & Bread")
    }

    // MARK: Android parity

    // Android sorts in SQL (shop, categoryId, name), so items inside one category and
    // the COMPLETED section come out by name, not by insertion order.
    func testItemsInOneCategorySortByName() {
        let vm = ListDetailViewModel(items: [
            ShoppingItem(id: "b", name: "Bananas", quantity: "6", categoryId: "cat-fruits-vegetables", shop: "Aldi"),
            ShoppingItem(id: "a", name: "Apples", quantity: "4", categoryId: "cat-fruits-vegetables", shop: "Aldi"),
            ShoppingItem(id: "z", name: "Zucchini", quantity: "1", isPickedUp: true),
            ShoppingItem(id: "y", name: "Yoghurt", quantity: "1", categoryId: "cat-dairy-eggs", isPickedUp: true),
            ShoppingItem(id: "c", name: "Carrots", quantity: "1", isPickedUp: true),
        ])
        XCTAssertEqual(vm.activeGroups[0].categories[0].items.map(\.name), ["Apples", "Bananas"])
        // No shop for all three; the categorised one first, then by name.
        XCTAssertEqual(vm.completedItems.map(\.name), ["Yoghurt", "Carrots", "Zucchini"])
    }

    func testShopsSortWithNoShopLastAndCategoriesByName() {
        let vm = ListDetailViewModel(items: [
            ShoppingItem(id: "1", name: "Soap", quantity: "1", categoryId: "cat-household-cleaning"),
            ShoppingItem(id: "2", name: "Steak", quantity: "1", categoryId: "cat-meat-seafood", shop: "Costco"),
            ShoppingItem(id: "3", name: "Milk", quantity: "1", categoryId: "cat-dairy-eggs", shop: "Costco"),
            ShoppingItem(id: "4", name: "Tape", quantity: "1", shop: "Bunnings"),
        ])
        XCTAssertEqual(vm.activeGroups.map(\.shop), ["Bunnings", "Costco", nil])
        XCTAssertEqual(vm.activeGroups[1].categories.map(\.name), ["Dairy & Eggs", "Meat & Seafood"])
    }

    func testNoShopGroupIsHeadedGeneralOnlyWhenOtherShopsExist() throws {
        let mixed = ListDetailViewModel(items: [
            ShoppingItem(id: "1", name: "Soap", quantity: "1"),
            ShoppingItem(id: "2", name: "Milk", quantity: "1", shop: "Aldi"),
        ])
        let general = try XCTUnwrap(mixed.activeGroups.last)
        XCTAssertNil(general.shop)
        XCTAssertEqual(general.title, "General")
        XCTAssertTrue(mixed.showsShopHeader(general))

        let noShops = ListDetailViewModel(items: [ShoppingItem(id: "1", name: "Soap", quantity: "1")])
        XCTAssertEqual(noShops.activeGroups.count, 1)
        XCTAssertFalse(noShops.showsShopHeader(noShops.activeGroups[0]))
    }

    func testCategoryHeadersHiddenWhenTheOnlyBucketIsUncategorized() {
        let vm = ListDetailViewModel(items: [
            ShoppingItem(id: "1", name: "Soap", quantity: "1", shop: "Aldi"),
            ShoppingItem(id: "2", name: "Milk", quantity: "1", categoryId: "cat-dairy-eggs", shop: "Coles"),
            ShoppingItem(id: "3", name: "Tape", quantity: "1", shop: "Coles"),
        ])
        let aldi = vm.activeGroups[0]
        let coles = vm.activeGroups[1]
        XCTAssertTrue(aldi.hidesCategoryHeaders)
        XCTAssertFalse(coles.hidesCategoryHeaders)
        XCTAssertEqual(coles.categories.map(\.title), ["Dairy & Eggs", "Uncategorized"])
    }

    func testUnknownCategoryIdIsUncategorized() {
        let vm = ListDetailViewModel(items: [ShoppingItem(id: "1", name: "Thing", quantity: "1", categoryId: "cat-gone")])
        XCTAssertNil(vm.items[0].categoryName)
        XCTAssertEqual(vm.activeGroups[0].categories.map(\.name), [nil])
    }

    func testCategoryPickerUsesTheDefaultCategoriesByName() {
        let names = DefaultCategories.sortedByName.map(\.name)
        XCTAssertEqual(names.count, 48)
        XCTAssertEqual(names, names.sorted())
        XCTAssertEqual(names.first, "Accessories & Jewelry")
        XCTAssertEqual(DefaultCategories.name(for: "cat-dairy-eggs"), "Dairy & Eggs")
    }

    func testEmptyListShowsTheFirstItemPrompt() {
        let vm = ListDetailViewModel(items: [ShoppingItem(id: "x", name: "a", quantity: "1")])
        XCTAssertFalse(vm.isEmpty)
        vm.delete("x")
        XCTAssertTrue(vm.isEmpty)
    }

    func testUndoSnackbarCopyAndDurationMatchAndroid() {
        let vm = ListDetailViewModel(listId: "sample-sunday-roast")
        XCTAssertNil(vm.undoMessage)
        vm.delete("sr-red-wine")
        XCTAssertEqual(vm.undoMessage, "Red wine deleted")
        XCTAssertEqual(ListDetailViewModel.undoSnackbarDuration, .seconds(4))
    }
}
