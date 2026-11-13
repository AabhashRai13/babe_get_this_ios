/// Domain model for a list (Android `ShoppingList`).
struct ShoppingList: Equatable, Sendable, Identifiable {
    let id: String
    var name: String
    var createdAt: Int64
    var updatedAt: Int64
    var isLocked: Bool = false
    // Not stored on the row: counted by the catalog query.
    var itemCount: Int = 0
    var completedItemCount: Int = 0

    /// A list is completed when it has items and all of them are picked up.
    /// Empty lists are NOT completed: they are still waiting for items.
    var isCompleted: Bool { itemCount > 0 && completedItemCount == itemCount }
}

extension ShoppingListWithItemCount {
    func toDomain() -> ShoppingList {
        ShoppingList(
            id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, isLocked: isLocked,
            itemCount: itemCount, completedItemCount: completedItemCount)
    }
}

extension ShoppingListRecord {
    func toDomain() -> ShoppingList {
        ShoppingList(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, isLocked: isLocked)
    }
}

extension ShoppingList {
    /// A brand-new row: no owner, not shared, nothing pending. Callers set the owner.
    func toRecord() -> ShoppingListRecord {
        ShoppingListRecord(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, isLocked: isLocked)
    }
}
