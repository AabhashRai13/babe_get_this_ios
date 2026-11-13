import XCTest
@testable import BabeGetThis

/// Port of Android's ShoppingListShareTextTest.
final class ShoppingListShareTextTests: XCTestCase {
    private func item(_ name: String, quantity: String = "", pickedUp: Bool = false) -> ShoppingItem {
        ShoppingItem(id: name, name: name, quantity: quantity, isPickedUp: pickedUp)
    }

    func testDropsCheckedAndAddsSummary() {
        let text = ShoppingListShareText.format(
            listName: "Groceries",
            items: [item("Milk", quantity: "2kg"), item("Eggs"), item("Coffee", pickedUp: true)])
        XCTAssertTrue(text.contains("[ ] Milk (2kg)"))
        XCTAssertTrue(text.contains("[ ] Eggs"))
        XCTAssertFalse(text.contains("Coffee"))
        XCTAssertTrue(text.contains("(1 already picked up)"))
        XCTAssertTrue(text.contains("via Babe, Get This"))
    }

    func testBlankQuantityShowsNameOnly() {
        let text = ShoppingListShareText.format(listName: "L", items: [item("Bread")])
        XCTAssertTrue(text.contains("[ ] Bread\n"))
    }

    // A fully-completed list shares everything (an empty message would be worse); those
    // items still render as "[ ]". Deliberate, pinned here.
    func testAllCheckedSharesWholeListWithoutSummary() {
        let text = ShoppingListShareText.format(
            listName: "L", items: [item("Milk", pickedUp: true), item("Eggs", pickedUp: true)])
        XCTAssertTrue(text.contains("[ ] Milk"))
        XCTAssertTrue(text.contains("[ ] Eggs"))
        XCTAssertFalse(text.contains("already picked up"))
    }

    func testEmptyListStillCarriesTitleAndFooter() {
        let text = ShoppingListShareText.format(listName: "Groceries", items: [])
        XCTAssertTrue(text.contains("🛒 Groceries"))
        XCTAssertTrue(text.contains("via Babe, Get This"))
        XCTAssertFalse(text.contains("[ ]"))
    }

    func testNoneCheckedOmitsTheSummaryLine() {
        let text = ShoppingListShareText.format(listName: "L", items: [item("Milk"), item("Eggs")])
        XCTAssertTrue(text.contains("[ ] Milk"))
        XCTAssertTrue(text.contains("[ ] Eggs"))
        XCTAssertFalse(text.contains("already picked up"))
    }

    func testSummaryCountsEveryCheckedItem() {
        let text = ShoppingListShareText.format(
            listName: "L",
            items: [item("Milk"), item("Eggs", pickedUp: true), item("Bread", pickedUp: true),
                    item("Jam", pickedUp: true)])
        XCTAssertTrue(text.contains("(3 already picked up)"))
    }

    func testWhitespaceQuantityIsTreatedAsAbsent() {
        let text = ShoppingListShareText.format(listName: "L", items: [item("Bread", quantity: "   ")])
        XCTAssertTrue(text.contains("[ ] Bread\n"))
    }

    func testTheListNameIsUsedVerbatim() {
        let text = ShoppingListShareText.format(listName: "Mum's list — 2024", items: [item("Milk")])
        XCTAssertTrue(text.contains("🛒 Mum's list — 2024"))
    }

    func testAVeryLongItemNameIsNotTruncated() {
        let long = String(repeating: "x", count: 200)
        let text = ShoppingListShareText.format(listName: "L", items: [item(long)])
        XCTAssertTrue(text.contains("[ ] \(long)"))
    }
}
