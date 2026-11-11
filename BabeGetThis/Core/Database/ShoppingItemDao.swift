import GRDB

// Port of Android `ShoppingItemDao`, minus the Got This queries (pickedUpAt,
// locked item ids, names for hints): Got This is out of iOS v1.
struct ShoppingItemDao: Sendable {
    let writer: any DatabaseWriter

    // Shop (nulls last) → category (nulls last) → name: groups items by store,
    // then by aisle within each store.
    private static let orderedByListSQL = """
        SELECT * FROM shopping_items
        WHERE listId = ? AND deletedAt IS NULL
        ORDER BY
            CASE WHEN shop IS NULL THEN 1 ELSE 0 END,
            shop ASC,
            CASE WHEN categoryId IS NULL THEN 1 ELSE 0 END,
            categoryId ASC,
            name ASC
        """

    /// A list's live items in screen order.
    func itemsByListId(_ listId: String) async throws -> [ShoppingItemRecord] {
        try await writer.read { db in try Self.itemsOrdered(db, listId: listId) }
    }

    /// Live version of `itemsByListId(_:)`.
    func observeItemsByListId(_ listId: String) -> ValueObservation<ValueReducers.Fetch<[ShoppingItemRecord]>> {
        ValueObservation.tracking { db in try Self.itemsOrdered(db, listId: listId) }
    }

    /// A list's live items in no particular order (snapshot for undo-delete).
    func itemsByListIdOnce(_ listId: String) async throws -> [ShoppingItemRecord] {
        try await writer.read { db in
            try ShoppingItemRecord.fetchAll(
                db, sql: "SELECT * FROM shopping_items WHERE listId = ? AND deletedAt IS NULL", arguments: [listId])
        }
    }

    /// Android's `insertItem` is `@Insert(onConflict = REPLACE)`, and its callers
    /// rely on that upsert: `SyncEngine.apply` writes every incoming item row through
    /// it, and `ShoppingItemRepository.restoreItem` revives a tombstoned item with it.
    /// Same semantics here, as an `INSERT … ON CONFLICT DO UPDATE` upsert. Never
    /// REPLACE: that deletes the old row first.
    func insertItem(_ item: ShoppingItemRecord) async throws {
        try await writer.write { db in try item.upsert(db) }
    }

    /// Batch `insertItem`, in one transaction.
    func insertItems(_ items: [ShoppingItemRecord]) async throws {
        try await writer.write { db in
            for item in items { try item.upsert(db) }
        }
    }

    func updateItem(_ item: ShoppingItemRecord) async throws {
        try await writer.write { db in try item.update(db) }
    }

    func deleteItem(id: String) async throws {
        try await execute("DELETE FROM shopping_items WHERE id = ?", [id])
    }

    /// A tick or untick.
    func setPickedUp(itemId: String, isPickedUp: Bool, updatedAt: Int64, pendingSync: Bool) async throws {
        try await execute(
            "UPDATE shopping_items SET isPickedUp = ?, updatedAt = ?, pendingSync = ? WHERE id = ?",
            [isPickedUp, updatedAt, pendingSync, itemId])
    }

    // MARK: - Sync primitives

    func softDeleteItem(id: String, now: Int64) async throws {
        try await execute(
            "UPDATE shopping_items SET deletedAt = :now, updatedAt = :now, pendingSync = 1 WHERE id = :id",
            ["id": id, "now": now])
    }

    /// The push's read: one account's pending items, tombstones included.
    /// Deliberately no unscoped variant.
    func pendingSyncItemsForAccount(_ accountId: String) async throws -> [ShoppingItemRecord] {
        try await writer.read { db in
            try ShoppingItemRecord.fetchAll(db, sql: """
                SELECT i.* FROM shopping_items i
                JOIN shopping_lists l ON l.id = i.listId
                WHERE i.pendingSync = 1 AND l.accountId = ?
                """, arguments: [accountId])
        }
    }

    func countPendingSyncItemsForAccount(_ accountId: String) async throws -> Int {
        try await fetchInt("""
            SELECT COUNT(*) FROM shopping_items i
            JOIN shopping_lists l ON l.id = i.listId
            WHERE i.pendingSync = 1 AND l.accountId = ?
            """, [accountId])
    }

    /// Guarded clear: only if the row wasn't edited again mid-push.
    func markItemSynced(id: String, updatedAt: Int64) async throws {
        try await execute("UPDATE shopping_items SET pendingSync = 0 WHERE id = ? AND updatedAt = ?", [id, updatedAt])
    }

    /// Sync-internal read with NO tombstone filter.
    func itemRaw(id: String) async throws -> ShoppingItemRecord? {
        try await writer.read { db in try ShoppingItemRecord.fetchOne(db, key: id) }
    }

    func countActiveItems() async throws -> Int {
        try await fetchInt("SELECT COUNT(*) FROM shopping_items WHERE deletedAt IS NULL")
    }

    func countPendingSync() async throws -> Int {
        try await fetchInt("SELECT COUNT(*) FROM shopping_items WHERE pendingSync = 1")
    }

    // MARK: - Helpers

    private static func itemsOrdered(_ db: Database, listId: String) throws -> [ShoppingItemRecord] {
        try ShoppingItemRecord.fetchAll(db, sql: orderedByListSQL, arguments: [listId])
    }

    private func execute(_ sql: String, _ arguments: StatementArguments) async throws {
        try await writer.write { db in try db.execute(sql: sql, arguments: arguments) }
    }

    private func fetchInt(_ sql: String, _ arguments: StatementArguments = StatementArguments()) async throws -> Int {
        try await writer.read { db in try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0 }
    }
}
