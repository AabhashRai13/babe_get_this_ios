import XCTest
@testable import BabeGetThis

/// Covers the quantity + unit flatten (TranscribeItemDto -> TranscribedItem) and the mapping to ItemDraft.
final class ToItemDraftTests: XCTestCase {
    private func draft(_ dto: TranscribeItemDto) -> ItemDraft {
        dto.toTranscribedItem().toItemDraft()
    }

    func testFlattensQuantityAndUnitIntoOneString() {
        XCTAssertEqual(draft(TranscribeItemDto(name: "Milk", quantity: 2, unit: "bottles")).quantity, "2 bottles")
    }

    func testQuantityWithNoUnitIsJustTheNumber() {
        XCTAssertEqual(draft(TranscribeItemDto(name: "Eggs", quantity: 12, unit: nil)).quantity, "12")
    }

    func testNoQuantityAndNoUnitBecomesEmpty() {
        XCTAssertEqual(draft(TranscribeItemDto(name: "Bread")).quantity, "")
    }

    func testUnitWithNoQuantityFallsBackToJustTheUnit() {
        XCTAssertEqual(draft(TranscribeItemDto(name: "Water", quantity: nil, unit: "bottles")).quantity, "bottles")
    }

    func testCarriesNameCategoryAndNoteThroughVerbatim() {
        let result = draft(TranscribeItemDto(name: "Milk", category: "cat-dairy-eggs", note: "the cold one"))
        XCTAssertEqual(result.name, "Milk")
        XCTAssertEqual(result.categoryId, "cat-dairy-eggs")
        XCTAssertEqual(result.note, "the cold one")
    }

    /// The backend field is "location"; the app calls it shop.
    func testLocationBecomesShop() {
        XCTAssertEqual(draft(TranscribeItemDto(name: "Wine", location: "Dan Murphy's")).shop, "Dan Murphy's")
    }

    func testAbsentOptionalFieldsStayEmpty() {
        let result = draft(TranscribeItemDto(name: "Bread"))
        XCTAssertNil(result.categoryId)
        XCTAssertEqual(result.note, "")
        XCTAssertEqual(result.shop, "")
        XCTAssertEqual(result.quantity, "")
    }

    func testBlankUnitWithNoQuantityCollapsesToEmpty() {
        XCTAssertEqual(draft(TranscribeItemDto(name: "Water", quantity: nil, unit: "   ")).quantity, "")
    }

    func testZeroQuantityIsKeptRatherThanTreatedAsAbsent() {
        XCTAssertEqual(draft(TranscribeItemDto(name: "Milk", quantity: 0)).quantity, "0")
    }

    func testNegativeQuantityIsCarriedThroughAsIs() {
        // Nothing validates this today; pinned so a future guard is a deliberate change.
        XCTAssertEqual(draft(TranscribeItemDto(name: "Milk", quantity: -1)).quantity, "-1")
    }

    func testEmptyNameIsCarriedThrough() {
        // The repository, not the mapper, is where blank names are rejected.
        XCTAssertEqual(draft(TranscribeItemDto(name: "")).name, "")
    }

    func testTranscribedItemMapsDirectly() {
        let item = TranscribedItem(name: "Tea", quantity: "3", note: "green", category: "cat-x", shop: "Aldi")
        XCTAssertEqual(
            item.toItemDraft(),
            ItemDraft(name: "Tea", quantity: "3", categoryId: "cat-x", shop: "Aldi", note: "green")
        )
    }

    /// Most spoken items have no quantity. They fail the manual add rule (quantity required,
    /// unchanged) but are savable voice items, so the persist path must not use `isValid`.
    func testASpokenItemWithoutQuantityFailsTheManualRuleButIsSavable() {
        let draft = TranscribedItem(name: "Bread").toItemDraft()
        XCTAssertFalse(draft.isValid)
        XCTAssertTrue(draft.isSavableVoiceItem)
    }

    func testABlankSpokenNameIsNotSavable() {
        XCTAssertFalse(TranscribedItem(name: "  ").toItemDraft().isSavableVoiceItem)
    }
}
