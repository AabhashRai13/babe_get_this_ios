import XCTest
@testable import BabeGetThis

/// Android CreateListDialogTest, on the dialog's pure state (the typed text, the 40-character
/// rule, the confirm button and what confirming returns).
final class CreateListDialogTests: XCTestCase {
    private func create() -> CreateListDialogState { CreateListDialogState() }
    private func edit(_ name: String = "Groceries") -> CreateListDialogState {
        CreateListDialogState(currentName: name)
    }

    func testCreateModeShowsTheNewListTitleAndAnEmptyField() {
        let dialog = create()

        XCTAssertEqual(dialog.title, "New List")
        XCTAssertEqual(dialog.confirmTitle, "Create")
        XCTAssertEqual(dialog.fieldLabel, "List name")
        XCTAssertEqual(dialog.name, "")
    }

    func testConfirmIsDisabledUntilANameIsTyped() {
        var dialog = create()
        XCTAssertFalse(dialog.isConfirmEnabled)

        dialog.type("Groceries")

        XCTAssertTrue(dialog.isConfirmEnabled)
    }

    func testConfirmStaysDisabledForWhitespaceOnly() {
        var dialog = create()
        dialog.type("   ")
        XCTAssertFalse(dialog.isConfirmEnabled)
        XCTAssertNil(dialog.confirm())
    }

    func testCreatingPassesTheTypedName() {
        var dialog = create()
        dialog.type("Groceries")
        XCTAssertEqual(dialog.confirm(), .create("Groceries"))
    }

    func testTheCreatedNameIsTrimmed() {
        var dialog = create()
        dialog.type("  Groceries  ")
        XCTAssertEqual(dialog.confirm(), .create("Groceries"))
    }

    func testANameOfExactlyFortyCharactersIsAccepted() {
        var dialog = create()
        dialog.type(String(repeating: "x", count: 40))
        guard case .create(let name) = dialog.confirm() else { return XCTFail("expected create") }
        XCTAssertEqual(name.count, 40)
    }

    /// Android pins the same behaviour: an over-long value is rejected wholesale, not clipped.
    func testPastingMoreThanFortyCharactersIsRejectedOutright() {
        var dialog = create()
        dialog.type(String(repeating: "x", count: 41))

        XCTAssertEqual(dialog.name, "")
        XCTAssertFalse(dialog.isConfirmEnabled)
        XCTAssertNil(dialog.confirm())
    }

    func testTypingStopsAtFortyCharacters() {
        var dialog = create()
        dialog.type(String(repeating: "x", count: 40))
        dialog.type(dialog.name + "y")
        XCTAssertEqual(dialog.name.count, 40)
    }

    func testCounterAppearsFromFortyCharacters() {
        var dialog = create()
        dialog.type(String(repeating: "x", count: 39))
        XCTAssertNil(dialog.counterText)
        dialog.type(String(repeating: "x", count: 40))
        XCTAssertEqual(dialog.counterText, "40/40")
    }

    func testEditModePrefillsTheCurrentNameAndOffersSave() {
        let dialog = edit("Groceries")

        XCTAssertEqual(dialog.title, "Rename List")
        XCTAssertEqual(dialog.name, "Groceries")
        XCTAssertEqual(dialog.confirmTitle, "Save")
    }

    func testEditModeRenamesRatherThanCreating() {
        var dialog = edit("Groceries")
        dialog.type("Hardware")
        XCTAssertEqual(dialog.confirm(), .rename("Hardware"))
    }

    func testEditModeDisablesSaveWhenTheNameIsCleared() {
        var dialog = edit("Groceries")
        dialog.type("")
        XCTAssertFalse(dialog.isConfirmEnabled)
        XCTAssertNil(dialog.confirm())
    }

    // MARK: - The field's rule (the text field binds `name` and reverts an over-long value)

    func testAnOverLongEditIsRevertedToThePreviousName() {
        var dialog = create()
        dialog.name = String(repeating: "x", count: 40)
        let previous = dialog.name
        dialog.name += "y"

        dialog.revertIfTooLong(previous: previous)

        XCTAssertEqual(dialog.name, previous)
    }

    func testAnOverLongPasteIntoAnEmptyFieldLeavesItEmpty() {
        var dialog = create()
        dialog.name = String(repeating: "x", count: 45)

        dialog.revertIfTooLong(previous: "")

        XCTAssertEqual(dialog.name, "")
    }

    func testAnEditWithinTheLimitIsKept() {
        var dialog = create()
        dialog.name = "Groceries"
        dialog.revertIfTooLong(previous: "Grocerie")
        XCTAssertEqual(dialog.name, "Groceries")
    }
}
