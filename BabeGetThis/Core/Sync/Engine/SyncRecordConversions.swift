// Stored GRDB records ↔ the remote layer's local record copies (LocalRecords.swift).
// The two are field-for-field the same; the remote layer keeps its own copy so it
// has no dependency on the database, and the engine converts at the boundary.

extension ShoppingListRecord {
    var syncLocal: LocalListRecord {
        LocalListRecord(
            id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, isLocked: isLocked,
            shareCode: shareCode, deletedAt: deletedAt, pendingSync: pendingSync,
            accountId: accountId, onServer: onServer)
    }

    init(syncLocal local: LocalListRecord) {
        self.init(
            id: local.id, name: local.name, createdAt: local.createdAt, updatedAt: local.updatedAt,
            isLocked: local.isLocked, shareCode: local.shareCode, deletedAt: local.deletedAt,
            pendingSync: local.pendingSync, accountId: local.accountId, onServer: local.onServer)
    }
}

extension ShoppingItemRecord {
    var syncLocal: LocalItemRecord {
        LocalItemRecord(
            id: id, listId: listId, name: name, quantity: quantity, isPickedUp: isPickedUp,
            categoryId: categoryId, shop: shop, note: note, createdAt: createdAt, updatedAt: updatedAt,
            deletedAt: deletedAt, pendingSync: pendingSync)
    }

    init(syncLocal local: LocalItemRecord) {
        self.init(
            id: local.id, listId: local.listId, name: local.name, quantity: local.quantity,
            isPickedUp: local.isPickedUp, categoryId: local.categoryId, shop: local.shop, note: local.note,
            createdAt: local.createdAt, updatedAt: local.updatedAt, deletedAt: local.deletedAt,
            pendingSync: local.pendingSync)
    }
}
