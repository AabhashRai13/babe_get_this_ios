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
            ShoppingItem(id: "b", name: "Milk", quantity: "2 L", category: nil, shop: "Aldi"),
            ShoppingItem(id: "c", name: "Eggs", quantity: "12", category: "Dairy & Eggs", shop: "Aldi"),
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
        XCTAssertTrue(vm.add(ItemDraft(name: " Bread ", quantity: "2", category: "Bakery & Bread", shop: " Aldi ", note: "  ")))
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items[0].name, "Bread")
        XCTAssertEqual(vm.items[0].shop, "Aldi")
        XCTAssertNil(vm.items[0].note)
        XCTAssertFalse(vm.items[0].isPickedUp)
    }
}
