import Foundation

// The local side of the sync mappers: plain value copies of Android's `ShoppingListEntity` and
// `ShoppingItemEntity`. They live here so the remote layer has no dependency on the database layer;
// the sync engine converts between these and the stored records. All times are epoch milliseconds.

struct LocalListRecord: Equatable, Sendable {
    var id: String
    var name: String
    var createdAt: Int64
    var updatedAt: Int64
    /// Per-device PIN lock. Never syncs.
    var isLocked: Bool = false
    /// Non-nil only when the list is shared.
    var shareCode: String? = nil
    /// Tombstone.
    var deletedAt: Int64? = nil
    /// Dirty flag: local changes not yet pushed. This is the outbox.
    var pendingSync: Bool = false
    /// The account this list belongs to; nil is a guest list that never syncs (docs/technical-decisions/008).
    var accountId: String? = nil
    /// The row exists on the server: a brand-new row's first push is a plain INSERT, later ones upsert.
    var onServer: Bool = false
}

struct LocalItemRecord: Equatable, Sendable {
    var id: String
    var listId: String
    var name: String
    var quantity: String
    var isPickedUp: Bool = false
    var categoryId: String? = nil
    var shop: String? = nil
    var note: String? = nil
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64? = nil
    var pendingSync: Bool = false
}
