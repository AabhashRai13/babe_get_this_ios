import Foundation
import GRDB

/// Port of Android `ShoppingItemRepository` minus Got This (`TickStore`, `pickedUpAt`)
/// and reminders, which are out of iOS v1. Writes go through `safeCall`.
///
/// One raw lookup decides every write's sync behaviour: items of account lists (shared
/// or not, Android docs/technical-decisions/008) are marked pendingSync and kick a push;
/// guest-list items never leave the device.
struct ShoppingItemRepository: Sendable {
    private let itemDao: ShoppingItemDao
    private let categoryDao: CategoryDao
    private let listDao: ShoppingListDao
    private let syncKicker: any SyncKicking
    private let safeCall: SafeCall

    init(
        itemDao: ShoppingItemDao,
        categoryDao: CategoryDao,
        listDao: ShoppingListDao,
        syncKicker: any SyncKicking,
        safeCall: SafeCall
    ) {
        self.itemDao = itemDao
        self.categoryDao = categoryDao
        self.listDao = listDao
        self.syncKicker = syncKicker
        self.safeCall = safeCall
    }

    private func isSynced(_ listId: String) async throws -> Bool {
        try await listDao.listRaw(id: listId)?.accountId != nil
    }

    // MARK: - Reads

    /// A list's live items in screen order, with category names resolved. Re-emits when
    /// either the items or the categories change.
    func itemsByListId(_ listId: String) -> AsyncThrowingStream<[StoredShoppingItem], any Error> {
        let itemValues = itemDao.observeItemsByListId(listId).values(in: itemDao.writer)
        let categoryValues = categoryDao.observeAllCategories().values(in: categoryDao.writer)
        return AsyncThrowingStream { continuation in
            // Flow.combine: emit once both sides have a value, then on every change.
            let latest = LatestPair()
            let emit: @Sendable () -> Void = {
                if let (items, categories) = latest.both {
                    let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
                    continuation.yield(items.map { $0.toStored(categoryName: $0.categoryId.flatMap { names[$0] }) })
                }
            }
            let itemsTask = Task {
                do {
                    for try await items in itemValues {
                        latest.set(items: items)
                        emit()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let categoriesTask = Task {
                do {
                    for try await categories in categoryValues {
                        latest.set(categories: categories)
                        emit()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                itemsTask.cancel()
                categoriesTask.cancel()
            }
        }
    }

    /// Latest value from each observation; the lock also orders the two emitters.
    private final class LatestPair: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ShoppingItemRecord]?
        private var categories: [CategoryRecord]?

        var both: ([ShoppingItemRecord], [CategoryRecord])? {
            lock.withLock { items.flatMap { items in categories.map { (items, $0) } } }
        }

        func set(items: [ShoppingItemRecord]) { lock.withLock { self.items = items } }
        func set(categories: [CategoryRecord]) { lock.withLock { self.categories = categories } }
    }

    // MARK: - Writes

    func addItem(
        listId: String,
        name: String,
        quantity: String,
        categoryId: String? = nil,
        shop: String? = nil,
        note: String? = nil
    ) async throws -> Result<String, AppError> {
        try await safeCall {
            let now = Self.nowMillis()
            let id = UUID().uuidString.lowercased()
            // Validated here, not only in the dialog: this is the trust boundary, and
            // voice-transcribed drafts reach the same table without a dialog.
            let item = StoredShoppingItem(
                id: id, listId: listId, name: try Self.requireItemName(name), quantity: quantity,
                categoryId: categoryId, shop: shop, note: note, createdAt: now, updatedAt: now)
            let synced = try await isSynced(listId)
            var record = item.toRecord()
            record.pendingSync = synced
            try await itemDao.insertItem(record)
            if synced { syncKicker.pushSoon() }
            return id
        }
    }

    func updateItem(_ item: StoredShoppingItem) async throws -> Result<Void, AppError> {
        try await safeCall {
            var updated = item
            updated.updatedAt = Self.nowMillis()
            let synced = try await isSynced(item.listId)
            var record = updated.toRecord()
            record.pendingSync = synced
            try await itemDao.updateItem(record)
            if synced { syncKicker.pushSoon() }
        }
    }

    /// A missing item is a quiet no-op. iOS v1 never writes `picked_up_at`.
    func togglePickedUp(itemId: String, isPickedUp: Bool) async throws -> Result<Void, AppError> {
        try await safeCall {
            guard let row = try await itemDao.itemRaw(id: itemId) else { return }
            let synced = try await isSynced(row.listId)
            try await itemDao.setPickedUp(
                itemId: itemId, isPickedUp: isPickedUp, updatedAt: Self.nowMillis(), pendingSync: synced)
            if synced { syncKicker.pushSoon() }
        }
    }

    func deleteItem(itemId: String) async throws -> Result<Void, AppError> {
        try await safeCall {
            let listId = try await itemDao.itemRaw(id: itemId)?.listId
            if let listId, try await isSynced(listId) {
                // Tombstone, not DELETE: the deletion itself must sync.
                try await itemDao.softDeleteItem(id: itemId, now: Self.nowMillis())
                syncKicker.pushSoon()
            } else {
                try await itemDao.deleteItem(id: itemId)
            }
        }
    }

    /// Re-inserts a previously deleted item with its original id (undo). For account-list
    /// items the row is only tombstoned, so the upsert clears `deletedAt` and the dirty
    /// flag pushes the revival to members.
    func restoreItem(_ item: StoredShoppingItem) async throws -> Result<Void, AppError> {
        try await safeCall {
            let synced = try await isSynced(item.listId)
            var record = item.toRecord()
            record.pendingSync = synced
            try await itemDao.insertItem(record)
            if synced { syncKicker.pushSoon() }
        }
    }

    // MARK: - Helpers

    /// Trims and rejects blank names as a validation error through safeCall.
    private static func requireItemName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw AppErrorException(.validation("Item name can't be empty."))
        }
        return trimmed
    }

    private static func nowMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}
