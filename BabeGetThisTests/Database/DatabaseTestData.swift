@testable import BabeGetThis

// Builders with sensible defaults (port of Android `testing/TestData`), so a test
// names only the fields it asserts on. Timestamps are fixed, never "now".
enum TestData {
    // 2024-06-01T00:00:00Z.
    static let t0: Int64 = 1_717_200_000_000
    static let day: Int64 = 24 * 60 * 60 * 1000

    static func listEntity(
        id: String = "list-1",
        name: String = "Groceries",
        createdAt: Int64 = t0,
        updatedAt: Int64 = t0,
        isLocked: Bool = false
    ) -> ShoppingListRecord {
        ShoppingListRecord(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, isLocked: isLocked)
    }

    static func itemEntity(
        id: String = "item-1",
        listId: String = "list-1",
        name: String = "Milk",
        quantity: String = "1",
        isPickedUp: Bool = false,
        categoryId: String? = nil,
        shop: String? = nil,
        note: String? = nil,
        createdAt: Int64 = t0,
        updatedAt: Int64 = t0
    ) -> ShoppingItemRecord {
        ShoppingItemRecord(
            id: id, listId: listId, name: name, quantity: quantity, isPickedUp: isPickedUp,
            categoryId: categoryId, shop: shop, note: note, createdAt: createdAt, updatedAt: updatedAt)
    }

    static func categoryEntity(id: String = "cat-1", name: String = "Dairy", isDefault: Bool = true) -> CategoryRecord {
        CategoryRecord(id: id, name: name, isDefault: isDefault)
    }
}

// Kotlin's `copy(...)` for the records.
protocol Copyable {}

extension Copyable {
    func with(_ change: (inout Self) -> Void) -> Self {
        var copy = self
        change(&copy)
        return copy
    }
}

extension ShoppingListRecord: Copyable {}
extension ShoppingItemRecord: Copyable {}
