import Foundation

/// Builds the plain-text representation of a list for the system share sheet
/// (Android `ShoppingListShareText`). Pure (name, items) -> String.
enum ShoppingListShareText {
    private static let footer = "via Babe, Get This"

    static func format(listName: String, items: [ShoppingItem]) -> String {
        let unchecked = items.filter { !$0.isPickedUp }
        // All picked up -> share the whole list rather than an empty message.
        let toList = unchecked.isEmpty ? items : unchecked
        let pickedUpCount = unchecked.isEmpty ? 0 : items.count - unchecked.count

        var text = "🛒 \(listName)\n\n"
        for item in toList {
            text += "[ ] \(item.name)"
            if !item.quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text += " (\(item.quantity))"
            }
            text += "\n"
        }
        if pickedUpCount > 0 {
            text += "\n(\(pickedUpCount) already picked up)\n"
        }
        text += "\n\(footer)"
        return text
    }
}
