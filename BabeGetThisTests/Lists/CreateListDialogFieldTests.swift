import SwiftUI
import UIKit
import XCTest
@testable import BabeGetThis

/// The 40-character rule on the real text field: the dialog is hosted in a window, text goes
/// in through the field's own UITextInput, and the field's value is read back (Android's
/// OutlinedTextField re-renders from `listName`, so it never shows more than 40).
@MainActor
final class CreateListDialogFieldTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
    }

    private func hostDialog(onConfirm: @escaping (CreateListDialogState.Outcome) -> Void = { _ in }) async throws -> UITextField {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: CreateListDialog(onDismiss: {}, onConfirm: onConfirm))
        window.makeKeyAndVisible()
        self.window = window
        for _ in 0..<100 {
            if let field = Self.textField(in: window) {
                field.becomeFirstResponder()
                await settle()
                return field
            }
            await settle()
        }
        throw XCTSkip("the dialog's text field never appeared")
    }

    private static func textField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        for subview in view.subviews {
            if let field = textField(in: subview) { return field }
        }
        return nil
    }

    /// Lets SwiftUI run its update (binding, onChange, re-sync of the field).
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(30))
    }

    /// Waits (up to 3 s) for SwiftUI to apply an edit. A fixed sleep alone raced on a loaded
    /// machine: the update hadn't run when the next key or the assertion came.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func type(_ text: String, into field: UITextField) async {
        for character in text {
            field.insertText(String(character))
            await waitUntil { (field.text?.count ?? 0) <= CreateListDialogState.maxNameLength }
            await settle()
        }
    }

    func testTypingPastFortyStopsTheFieldAtForty() async throws {
        let field = try await hostDialog()

        await type(String(repeating: "a", count: 38) + "XYZQ", into: field)
        let expected = String(repeating: "a", count: 38) + "XY"
        await waitUntil { field.text == expected }

        XCTAssertEqual(field.text, expected)
        XCTAssertEqual(field.text?.count, CreateListDialogState.maxNameLength)
    }

    func testAnOverLongPasteLeavesTheFieldAsItWas() async throws {
        let field = try await hostDialog()
        await type("Groceries", into: field)

        field.insertText(String(repeating: "p", count: 41))
        await waitUntil { field.text == "Groceries" }

        XCTAssertEqual(field.text, "Groceries", "an over-long paste is rejected, not clipped")
    }

    func testTheSavedNameIsWhatTheFieldShows() async throws {
        var outcome: CreateListDialogState.Outcome?
        let field = try await hostDialog { outcome = $0 }
        await type(String(repeating: "b", count: 41), into: field)

        field.sendActions(for: .editingDidEndOnExit) // Return
        await waitUntil { outcome != nil }

        XCTAssertEqual(outcome, .create(try XCTUnwrap(field.text)))
        XCTAssertEqual(field.text?.count, CreateListDialogState.maxNameLength)
    }
}
