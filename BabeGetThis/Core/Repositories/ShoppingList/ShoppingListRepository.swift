import Foundation
import GRDB

/// Port of Android `ShoppingListRepository`: create, create-with-items, rename and
/// add-items, routed to whoever owns the device's lists. Delete and undo come later.
///
/// Streams don't need Result wrapping; GRDB errors end the stream. Writes go
/// through `safeCall` and come back as `Result<T, AppError>`.
struct ShoppingListRepository: Sendable {
    private let listDao: ShoppingListDao
    private let itemDao: ShoppingItemDao
    private let categoryDao: CategoryDao
    private let authStateManager: AuthStateManager
    private let syncKicker: any SyncKicking
    private let safeCall: SafeCall

    init(
        listDao: ShoppingListDao,
        itemDao: ShoppingItemDao,
        categoryDao: CategoryDao,
        authStateManager: AuthStateManager,
        syncKicker: any SyncKicking,
        safeCall: SafeCall
    ) {
        self.listDao = listDao
        self.itemDao = itemDao
        self.categoryDao = categoryDao
        self.authStateManager = authStateManager
        self.syncKicker = syncKicker
        self.safeCall = safeCall
    }

    // MARK: - Reads

    /// One owner's lists at a time (Android docs/technical-decisions/008): the account's
    /// while signed in or after a lost session, the guest lists when signed out.
    /// Re-queries whenever the owner changes, so signing in or out swaps the
    /// screen's lists without anyone asking.
    func allLists() -> AsyncThrowingStream<[ShoppingList], any Error> {
        let owners = authStateManager.dataOwner
        let dao = listDao
        return AsyncThrowingStream { continuation in
            // flatMapLatest: cancelling the old query is only cooperative, and a value it has
            // already read could still be yielded after the new owner's. Each query gets a
            // generation and only the current one reaches the stream.
            let gate = OwnerGeneration()
            let task = Task {
                var current: Task<Void, Never>?
                for await owner in owners {
                    let generation = gate.advance()
                    current?.cancel()
                    current = Task {
                        do {
                            for try await rows in dao.observeListsWithItemCount(accountId: owner).values(in: dao.writer) {
                                let lists = rows.map { $0.toDomain() }
                                gate.ifCurrent(generation) { continuation.yield(lists) }
                            }
                        } catch is CancellationError {
                            // The owner changed; the next query has taken over.
                        } catch {
                            gate.ifCurrent(generation) { continuation.finish(throwing: error) }
                        }
                    }
                }
                gate.advance()
                current?.cancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Which owner query may emit. Advancing and the check-then-yield share one lock, so once
    /// `advance()` returns nothing from an older query reaches the stream.
    private final class OwnerGeneration: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0

        @discardableResult
        func advance() -> Int {
            lock.withLock {
                current += 1
                return current
            }
        }

        /// Runs `body` under the lock if `generation` is still current. `body` must not block.
        func ifCurrent(_ generation: Int, _ body: () -> Void) {
            lock.withLock {
                if generation == current { body() }
            }
        }
    }

    /// Every write to a list that has an owner goes through sync, shared or not.
    func isAccountList(_ listId: String) async throws -> Bool {
        try await listDao.listRaw(id: listId)?.accountId != nil
    }

    /// A live list, or nil when missing or tombstoned.
    func listById(_ listId: String) -> AsyncThrowingStream<ShoppingList?, any Error> {
        observeList(listId) { $0?.toDomain() }
    }

    /// Live share state of a list: nil while it's local-only (and again if it gets
    /// tombstoned). Drives the realtime subscription lifecycle on the items screen.
    func shareCode(listId: String) -> AsyncThrowingStream<String?, any Error> {
        observeList(listId) { $0?.shareCode }
    }

    // MARK: - Writes

    func createList(name: String) async throws -> Result<String, AppError> {
        try await safeCall {
            let now = Self.nowMillis()
            let id = UUID().uuidString.lowercased()
            // Validated and trimmed HERE, not only in the UI: this is the trust boundary,
            // and createListWithItems reaches the same table from transcribed voice input
            // that no dialog ever validated.
            let list = ShoppingList(id: id, name: try Self.requireListName(name), createdAt: now, updatedAt: now)
            let owner = authStateManager.dataOwnerId
            var record = list.toRecord()
            record.accountId = owner
            record.pendingSync = owner != nil
            try await listDao.insertList(record)
            if owner != nil { syncKicker.pushSoon() }
            return id
        }
    }

    /// Voice-capture entry point: a new list AND its items in one go. Per-item defaults
    /// match manually typed items. Returns the new list id so the caller can navigate into it.
    func createListWithItems(name: String, drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        try await safeCall {
            let now = Self.nowMillis()
            let listId = UUID().uuidString.lowercased()
            let list = ShoppingList(id: listId, name: try Self.requireListName(name), createdAt: now, updatedAt: now)

            // One transaction: two separate inserts left a list with none of its items
            // whenever anything failed or was cancelled in between, and the voice sheet
            // cancels this exact call on dismiss.
            let owner = authStateManager.dataOwnerId
            let synced = owner != nil
            var record = list.toRecord()
            record.accountId = owner
            record.pendingSync = synced
            let items = try await draftsToItems(listId: listId, drafts: drafts, now: now).map {
                var item = $0
                item.pendingSync = synced
                return item
            }
            try await listDao.insertListWithItems(record, items: items)
            if synced { syncKicker.pushSoon() }
            return listId
        }
    }

    /// Voice "add to existing list": appends spoken drafts to the open list. Returns
    /// the list id, mirroring createListWithItems.
    func addItemsToList(listId: String, drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        try await safeCall {
            let now = Self.nowMillis()
            let synced = try await isAccountList(listId)
            let items = try await draftsToItems(listId: listId, drafts: drafts, now: now).map {
                var item = $0
                if synced { item.pendingSync = true }
                return item
            }
            if !items.isEmpty {
                try await itemDao.insertItems(items)
                if synced { syncKicker.pushSoon() }
            }
            return listId
        }
    }

    func updateListName(listId: String, newName: String) async throws -> Result<Void, AppError> {
        try await safeCall {
            let now = Self.nowMillis()
            // NotFound rather than a bare error: safeCall maps unrecognised errors to
            // .unknown, and "List not found" must reach the user as real copy.
            guard var record = try await listDao.list(id: listId) else {
                throw Self.listNotFound()
            }
            let synced = record.accountId != nil
            record.name = try Self.requireListName(newName)
            record.updatedAt = now
            record.pendingSync = record.pendingSync || synced
            try await listDao.updateList(record)
            if synced { syncKicker.pushSoon() }
        }
    }

    /// Captures the items before deleting the list; the CASCADE wipes them on a hard
    /// delete, so the caller holds them for undo. Account lists soft-delete instead: the
    /// tombstone must survive and sync for the deletion to reach other members and the
    /// account's other phones, and the item rows stay hidden behind it. Even a list that
    /// hasn't reached the server yet gets a tombstone: a push may be uploading it right
    /// now, and only the push (serialised with that upload) can tell whether the
    /// tombstone must follow it or the row can simply go.
    func deleteListAndCaptureItems(listId: String) async throws -> Result<[ShoppingItemRecord], AppError> {
        try await safeCall {
            let items = try await itemDao.itemsByListIdOnce(listId)
            if try await isAccountList(listId) {
                try await listDao.softDeleteList(id: listId, now: Self.nowMillis())
                syncKicker.pushSoon()
            } else {
                try await listDao.deleteList(id: listId)
            }
            return items
        }
    }

    /// Undo for a delete: puts the list back with its items so derived fields such as
    /// `isCompleted` recompute correctly.
    func restoreListWithItems(list: ShoppingList, items: [ShoppingItemRecord]) async throws -> Result<Void, AppError> {
        try await safeCall {
            if var raw = try await listDao.listRaw(id: list.id), raw.accountId != nil {
                // Account list, soft-deleted: the rows never left the database, so undo
                // just clears the tombstone and pushes. Re-inserting from the domain
                // model would wipe accountId and shareCode and detach the list from
                // sync. UPDATE, never insert-or-replace: a REPLACE is DELETE + INSERT,
                // and the CASCADE would wipe every item of the restored list.
                raw.deletedAt = nil
                raw.updatedAt = Self.nowMillis()
                raw.pendingSync = true
                try await listDao.updateList(raw)
                syncKicker.pushSoon()
            } else {
                // The row is gone: a guest list, or an account list the push dropped
                // because it never reached the server. It comes back as a list of
                // whoever owns the device's lists now, as a new list would. One
                // transaction, so a half-done restore can't drop the cached items.
                let owner = authStateManager.dataOwnerId
                var record = list.toRecord()
                record.accountId = owner
                record.pendingSync = owner != nil
                let restored = owner == nil ? items : items.map {
                    var item = $0
                    item.pendingSync = true
                    return item
                }
                try await listDao.insertListWithItems(record, items: restored)
                if owner != nil { syncKicker.pushSoon() }
            }
        }
    }

    // MARK: - Helpers

    /// Draft → item row, shared by createListWithItems and addItemsToList. The trust-boundary
    /// guard lives here once: a backend category id is kept only if it names a real row.
    private func draftsToItems(listId: String, drafts: [ItemDraft], now: Int64) async throws -> [ShoppingItemRecord] {
        let knownCategoryIds = Set(try await categoryDao.allCategories().map(\.id))
        return drafts.map { draft in
            ShoppingItemRecord(
                id: UUID().uuidString.lowercased(),
                listId: listId,
                name: draft.name,
                // An absent quantity is already "" on the draft, matching typed items.
                quantity: draft.quantity,
                categoryId: draft.categoryId.flatMap { knownCategoryIds.contains($0) ? $0 : nil },
                shop: draft.shop.isEmpty ? nil : draft.shop,
                note: draft.note.isEmpty ? nil : draft.note,
                createdAt: now,
                updatedAt: now)
        }
    }

    /// Trims and rejects blank list names at the repository boundary, as a validation
    /// error through safeCall rather than a crash or a silently blank list.
    private static func requireListName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw AppErrorException(.validation("List name can't be empty."))
        }
        return trimmed
    }

    private static func listNotFound() -> AppErrorException {
        AppErrorException(.notFound("That list no longer exists."))
    }

    private static func nowMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }

    private func observeList<T: Sendable>(
        _ listId: String, _ transform: @escaping @Sendable (ShoppingListRecord?) -> T
    ) -> AsyncThrowingStream<T, any Error> {
        let values = listDao.observeList(id: listId).values(in: listDao.writer)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await record in values {
                        continuation.yield(transform(record))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
