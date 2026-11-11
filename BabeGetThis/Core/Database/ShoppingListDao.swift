import GRDB

// Port of Android `ShoppingListDao`. Each method is one transaction.
//
// A device shows exactly one owner's lists (Android docs/technical-decisions/008):
// the signed-in account's, or — accountId nil — the guest lists. An ownerless
// shared replica is neither, so it is hidden until an account claims it.
struct ShoppingListDao: Sendable {
    let writer: any DatabaseWriter

    // MARK: - Catalog

    /// One owner's live lists with live item and completion counts, newest first.
    func listsWithItemCount(accountId: String?) async throws -> [ShoppingListWithItemCount] {
        try await writer.read { db in try Self.listsWithItemCount(db, accountId: accountId) }
    }

    /// Live version of `listsWithItemCount(accountId:)`.
    func observeListsWithItemCount(
        accountId: String?
    ) -> ValueObservation<ValueReducers.Fetch<[ShoppingListWithItemCount]>> {
        ValueObservation.tracking { db in try Self.listsWithItemCount(db, accountId: accountId) }
    }

    /// The list edited last, finished or not. Item edits don't bump a list's
    /// updatedAt, so the later of it and its newest item's updatedAt (deleted
    /// items too) counts; ties go to the newer list.
    func mostRecentlyEdited(accountId: String?) async throws -> ShoppingListRecord? {
        try await writer.read { db in
            try ShoppingListRecord.fetchOne(db, sql: """
                SELECT l.* FROM shopping_lists l
                WHERE l.deletedAt IS NULL
                  AND ((:accountId IS NULL AND l.accountId IS NULL AND l.shareCode IS NULL)
                       OR l.accountId = :accountId)
                ORDER BY MAX(l.updatedAt, COALESCE((SELECT MAX(i.updatedAt) FROM shopping_items i WHERE i.listId = l.id), 0)) DESC,
                         l.createdAt DESC
                LIMIT 1
                """, arguments: ["accountId": accountId])
        }
    }

    /// A live (not tombstoned) list.
    func list(id: String) async throws -> ShoppingListRecord? {
        try await writer.read { db in try Self.liveList(db, id: id) }
    }

    /// Live version of `list(id:)`.
    func observeList(id: String) -> ValueObservation<ValueReducers.Fetch<ShoppingListRecord?>> {
        ValueObservation.tracking { db in try Self.liveList(db, id: id) }
    }

    // MARK: - Writes

    /// Plain INSERT of a brand-new list; throws if the id exists.
    func insertList(_ list: ShoppingListRecord) async throws {
        try await writer.write { db in try list.insert(db) }
    }

    /// UPDATE the row if it exists, otherwise INSERT it. Never REPLACE, which
    /// would delete the row and CASCADE its items away.
    func saveList(_ list: ShoppingListRecord) async throws {
        try await writer.write { db in try list.save(db) }
    }

    func updateList(_ list: ShoppingListRecord) async throws {
        try await writer.write { db in try list.update(db) }
    }

    /// A list and its items as one transaction, so a failure can't leave a list
    /// stripped of its items. Used by create-with-items and undo-restore.
    func insertListWithItems(_ list: ShoppingListRecord, items: [ShoppingItemRecord]) async throws {
        try await writer.write { db in
            try list.save(db)
            for item in items { try item.save(db) }
        }
    }

    func setLocked(listId: String, locked: Bool) async throws {
        try await execute("UPDATE shopping_lists SET isLocked = ? WHERE id = ?", [locked, listId])
    }

    /// Unlocks every list — used when the device PIN is removed.
    func unlockAll() async throws {
        try await execute("UPDATE shopping_lists SET isLocked = 0 WHERE isLocked = 1")
    }

    func lockedCount() async throws -> Int {
        try await fetchInt("SELECT COUNT(*) FROM shopping_lists WHERE isLocked = 1")
    }

    func lockedListIds() async throws -> [String] {
        try await fetchIds("SELECT id FROM shopping_lists WHERE isLocked = 1")
    }

    /// Hard delete; the CASCADE removes the items.
    func deleteList(id: String) async throws {
        try await execute("DELETE FROM shopping_lists WHERE id = ?", [id])
    }

    /// Deletes the list only if it has no items, in one atomic statement.
    /// Returns 1 if deleted, 0 if it had items or didn't exist.
    @discardableResult
    func deleteListIfEmpty(id: String) async throws -> Int {
        try await executeCountingChanges("""
            DELETE FROM shopping_lists
            WHERE id = :listId
              AND NOT EXISTS (SELECT 1 FROM shopping_items WHERE listId = :listId)
            """, ["listId": id])
    }

    // MARK: - Sync primitives (account lists)

    /// Tombstone variant of `deleteListIfEmpty` for account lists; counts live items only.
    @discardableResult
    func softDeleteListIfEmpty(id: String, now: Int64) async throws -> Int {
        try await executeCountingChanges("""
            UPDATE shopping_lists
            SET deletedAt = :now, updatedAt = :now, pendingSync = 1
            WHERE id = :listId
              AND deletedAt IS NULL
              AND NOT EXISTS (SELECT 1 FROM shopping_items WHERE listId = :listId AND deletedAt IS NULL)
            """, ["listId": id, "now": now])
    }

    /// The tombstone survives locally so the deletion itself can sync.
    func softDeleteList(id: String, now: Int64) async throws {
        try await execute(
            "UPDATE shopping_lists SET deletedAt = :now, updatedAt = :now, pendingSync = 1 WHERE id = :listId",
            ["listId": id, "now": now])
    }

    /// One account's unpushed rows, tombstones included.
    func pendingAccountLists(accountId: String) async throws -> [ShoppingListRecord] {
        try await writer.read { db in
            try ShoppingListRecord.fetchAll(
                db, sql: "SELECT * FROM shopping_lists WHERE pendingSync = 1 AND accountId = ?",
                arguments: [accountId])
        }
    }

    func countPendingAccountLists(accountId: String) async throws -> Int {
        try await fetchInt("SELECT COUNT(*) FROM shopping_lists WHERE pendingSync = 1 AND accountId = ?", [accountId])
    }

    /// Lists deleted before they ever reached the server: nothing to deliver, so drop them.
    func deleteNeverSentDeletedLists() async throws {
        try await execute("DELETE FROM shopping_lists WHERE onServer = 0 AND deletedAt IS NOT NULL")
    }

    func neverSentDeletedListIds() async throws -> [String] {
        try await fetchIds("SELECT id FROM shopping_lists WHERE onServer = 0 AND deletedAt IS NOT NULL")
    }

    func setShareCode(id: String, code: String) async throws {
        try await execute("UPDATE shopping_lists SET shareCode = ? WHERE id = ?", [code, id])
    }

    /// The first INSERT landed; every later push of this row is an upsert.
    func markListOnServer(id: String) async throws {
        try await execute("UPDATE shopping_lists SET onServer = 1 WHERE id = ?", [id])
    }

    /// Guarded clear: only if the row wasn't edited again mid-push.
    func markListSynced(id: String, updatedAt: Int64) async throws {
        try await execute("UPDATE shopping_lists SET pendingSync = 0 WHERE id = ? AND updatedAt = ?", [id, updatedAt])
    }

    /// Sync-internal read with NO tombstone filter: LWW must see deleted rows.
    func listRaw(id: String) async throws -> ShoppingListRecord? {
        try await writer.read { db in try ShoppingListRecord.fetchOne(db, key: id) }
    }

    func guestListIds() async throws -> [String] {
        try await fetchIds("SELECT id FROM shopping_lists WHERE accountId IS NULL AND deletedAt IS NULL")
    }

    func accountListIds(accountId: String) async throws -> [String] {
        try await fetchIds("SELECT id FROM shopping_lists WHERE accountId = ? AND deletedAt IS NULL", [accountId])
    }

    /// Gives an ownerless replica to the account the server just vouched for.
    func claimList(id: String, accountId: String) async throws {
        try await execute(
            "UPDATE shopping_lists SET accountId = ?, onServer = 1 WHERE id = ? AND accountId IS NULL",
            [accountId, id])
    }

    func countPendingSync() async throws -> Int {
        try await fetchInt("SELECT COUNT(*) FROM shopping_lists WHERE pendingSync = 1")
    }

    // MARK: - Claim on sign-in (Android docs/technical-decisions/008)

    func otherAccountListIds(userId: String) async throws -> [String] {
        try await fetchIds("SELECT id FROM shopping_lists WHERE accountId IS NOT NULL AND accountId != ?", [userId])
    }

    func ownerlessSharedListIds() async throws -> [String] {
        try await fetchIds("SELECT id FROM shopping_lists WHERE accountId IS NULL AND shareCode IS NOT NULL")
    }

    /// Undoes a first-run claim the server didn't confirm: back to ownerless.
    func releaseClaims(ids: [String], userId: String) async throws {
        guard !ids.isEmpty else { return }
        try await execute(
            "UPDATE shopping_lists SET accountId = NULL WHERE id IN (\(databaseQuestionMarks(count: ids.count))) AND accountId = ?",
            StatementArguments(ids + [userId]))
    }

    /// Everything a sign-in does to the device's lists, as one transaction.
    /// Drops another account's replicas, queues guest lists and their live items
    /// for upload, and takes ownerless shared replicas only when asked.
    /// Returns how many guest lists moved into the account.
    @discardableResult
    func claimDeviceLists(userId: String, includeOwnerlessShared: Bool) async throws -> Int {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM shopping_lists WHERE accountId IS NOT NULL AND accountId != ?", arguments: [userId])
            // Must run before the claim below: afterwards the subquery matches nothing.
            try db.execute(sql: """
                UPDATE shopping_items SET pendingSync = 1
                WHERE deletedAt IS NULL
                  AND listId IN (SELECT id FROM shopping_lists WHERE accountId IS NULL AND shareCode IS NULL)
                """)
            try db.execute(
                sql: "UPDATE shopping_lists SET accountId = ?, pendingSync = 1 WHERE accountId IS NULL AND shareCode IS NULL",
                arguments: [userId])
            let claimed = db.changesCount
            if includeOwnerlessShared {
                try db.execute(
                    sql: "UPDATE shopping_lists SET accountId = ? WHERE accountId IS NULL AND shareCode IS NOT NULL",
                    arguments: [userId])
            }
            return claimed
        }
    }

    /// Eviction on explicit sign-out: hard delete account lists and ownerless
    /// shared replicas (CASCADE clears items). Guest lists are untouched.
    func deleteAccountLists() async throws {
        try await execute("DELETE FROM shopping_lists WHERE accountId IS NOT NULL OR shareCode IS NOT NULL")
    }

    // MARK: - Helpers

    private static func listsWithItemCount(_ db: Database, accountId: String?) throws -> [ShoppingListWithItemCount] {
        try ShoppingListWithItemCount.fetchAll(db, sql: """
            SELECT l.id, l.name, l.createdAt, l.updatedAt, l.isLocked,
                   COUNT(i.id) AS itemCount,
                   COALESCE(SUM(CASE WHEN i.isPickedUp = 1 THEN 1 ELSE 0 END), 0) AS completedItemCount
            FROM shopping_lists l
            LEFT JOIN shopping_items i ON l.id = i.listId AND i.deletedAt IS NULL
            WHERE l.deletedAt IS NULL
              AND ((:accountId IS NULL AND l.accountId IS NULL AND l.shareCode IS NULL)
                   OR l.accountId = :accountId)
            GROUP BY l.id
            ORDER BY l.createdAt DESC
            """, arguments: ["accountId": accountId])
    }

    private static func liveList(_ db: Database, id: String) throws -> ShoppingListRecord? {
        try ShoppingListRecord.fetchOne(
            db, sql: "SELECT * FROM shopping_lists WHERE id = ? AND deletedAt IS NULL", arguments: [id])
    }

    private func execute(_ sql: String, _ arguments: StatementArguments = StatementArguments()) async throws {
        try await writer.write { db in try db.execute(sql: sql, arguments: arguments) }
    }

    private func executeCountingChanges(_ sql: String, _ arguments: StatementArguments) async throws -> Int {
        try await writer.write { db in
            try db.execute(sql: sql, arguments: arguments)
            return db.changesCount
        }
    }

    private func fetchInt(_ sql: String, _ arguments: StatementArguments = StatementArguments()) async throws -> Int {
        try await writer.read { db in try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0 }
    }

    private func fetchIds(_ sql: String, _ arguments: StatementArguments = StatementArguments()) async throws -> [String] {
        try await writer.read { db in try String.fetchAll(db, sql: sql, arguments: arguments) }
    }
}
