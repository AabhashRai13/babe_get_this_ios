/// Repository-level item (Android `ShoppingItem` domain model): the full row's fields
/// plus the resolved category name. Distinct from the view-layer `ShoppingItem`, which
/// carries no list id or timestamps.
struct StoredShoppingItem: Equatable, Sendable, Identifiable {
    let id: String
    var listId: String
    var name: String
    var quantity: String
    var isPickedUp: Bool = false
    var categoryId: String? = nil
    var categoryName: String? = nil
    var shop: String? = nil
    var note: String? = nil
    var createdAt: Int64
    var updatedAt: Int64
}

extension ShoppingItemRecord {
    func toStored(categoryName: String?) -> StoredShoppingItem {
        StoredShoppingItem(
            id: id, listId: listId, name: name, quantity: quantity, isPickedUp: isPickedUp,
            categoryId: categoryId, categoryName: categoryName, shop: shop, note: note,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension StoredShoppingItem {
    /// A clean row: callers set `pendingSync`.
    func toRecord() -> ShoppingItemRecord {
        ShoppingItemRecord(
            id: id, listId: listId, name: name, quantity: quantity, isPickedUp: isPickedUp,
            categoryId: categoryId, shop: shop, note: note, createdAt: createdAt, updatedAt: updatedAt)
    }
}
