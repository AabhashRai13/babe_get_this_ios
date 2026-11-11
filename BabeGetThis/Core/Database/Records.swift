import GRDB

// Row types for the local database, ported from the Android Room entities
// (ShoppingListEntity, ShoppingItemEntity, CategoryEntity). Column names match
// Android exactly. Timestamps are epoch milliseconds, like Android and the server.
//
// Existing rows are always changed with UPDATE (`update`, `save`, `updateAll`),
// never INSERT OR REPLACE: a REPLACE deletes the old row first, and the CASCADE
// on shopping_items would take the list's items with it.

struct ShoppingListRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "shopping_lists"

    var id: String
    var name: String
    var createdAt: Int64
    var updatedAt: Int64
    // Per-list lock. Never syncs: each device may lock its own replica.
    var isLocked: Bool = false
    // Nil = not shared.
    var shareCode: String? = nil
    // Tombstone (epoch millis). Account lists soft-delete so the deletion can
    // sync; guest lists are hard-deleted (CASCADE takes the items).
    var deletedAt: Int64? = nil
    // Dirty flag: true = local changes not yet pushed. This IS the outbox.
    var pendingSync: Bool = false
    // The owning account; nil is a guest list that lives on this device only.
    var accountId: String? = nil
    // The row exists on the server: the first push is a plain INSERT, every
    // later one an upsert.
    var onServer: Bool = false
}

// iOS v1 has no `pickedUpAt`: Got This is out of v1 (see CLAUDE.md).
struct ShoppingItemRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "shopping_items"

    var id: String
    var listId: String
    var name: String
    var quantity: String
    var isPickedUp: Bool = false
    var categoryId: String? = nil
    // Optional shop, e.g. "Costco".
    var shop: String? = nil
    var note: String? = nil
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64? = nil
    var pendingSync: Bool = false
}

struct CategoryRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "categories"

    var id: String
    var name: String
    // true = shipped default the user can't delete; false = user-created.
    var isDefault: Bool
}

// One row of the lists catalog: a list with its live item counts.
struct ShoppingListWithItemCount: Decodable, Equatable, Sendable, FetchableRecord {
    var id: String
    var name: String
    var createdAt: Int64
    var updatedAt: Int64
    var isLocked: Bool
    var itemCount: Int
    var completedItemCount: Int
}
