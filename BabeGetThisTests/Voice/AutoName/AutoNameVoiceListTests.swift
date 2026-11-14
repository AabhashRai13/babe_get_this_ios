import XCTest
@testable import BabeGetThis

/// Port of Android's AutoNameVoiceListTest: single / multiple / empty / blank / over-long.
final class AutoNameVoiceListTests: XCTestCase {
    private func draft(_ name: String) -> ItemDraft {
        var draft = ItemDraft()
        draft.name = name
        return draft
    }

    func testSingleItemUsesItsName() {
        XCTAssertEqual("Milk", autoNameVoiceList([draft("Milk")]))
    }

    func testMultipleItemsAppendPlusMore() {
        XCTAssertEqual("Milk + 2 more", autoNameVoiceList([draft("Milk"), draft("Eggs"), draft("Bread")]))
    }

    func testEmptyListFallsBackToList() {
        XCTAssertEqual("List", autoNameVoiceList([]))
    }

    func testBlankFirstNameFallsBackToList() {
        XCTAssertEqual("List", autoNameVoiceList([draft("   ")]))
    }

    func testOverLongFirstNameIsCappedAt40Chars() {
        let name = autoNameVoiceList([draft(String(repeating: "x", count: 100)), draft("Eggs")])
        XCTAssertEqual(String(repeating: "x", count: 40) + " + 1 more", name)
    }

    func testExactlyFortyCharsIsKeptWhole() {
        let name = String(repeating: "x", count: 40)
        XCTAssertEqual(name, autoNameVoiceList([draft(name)]))
    }

    func testFortyOneCharsLosesExactlyOne() {
        XCTAssertEqual(String(repeating: "x", count: 40),
                       autoNameVoiceList([draft(String(repeating: "x", count: 41))]))
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual("Milk", autoNameVoiceList([draft("  Milk  ")]))
    }

    func testBlankFirstNameWithOthersStillCountsThem() {
        XCTAssertEqual("List + 2 more", autoNameVoiceList([draft(""), draft("Eggs"), draft("Bread")]))
    }

    func testTwoItemsReadAsPlusOneMore() {
        XCTAssertEqual("Milk + 1 more", autoNameVoiceList([draft("Milk"), draft("Eggs")]))
    }
}
