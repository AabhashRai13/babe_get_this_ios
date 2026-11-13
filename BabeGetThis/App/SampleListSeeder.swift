import Foundation
import GRDB

/// Writes `ShoppingListSummary.samples` into a database as guest lists, so `-sampleData`
/// and previews run the real repository path. Sunday Roast gets its fixed items
/// (`ShoppingItem.sundayRoast`, for the detail screenshot); every other list gets
/// placeholder items, the first `pickedUpItems` of them picked up.
enum SampleListSeeder {
    static func seed(_ database: AppDatabase, lists: [ShoppingListSummary] = ShoppingListSummary.samples) throws {
        let now = Int64((Date().timeIntervalSince1970 * 1000).rounded())
        try database.writer.write { db in
            for (offset, list) in lists.enumerated() {
                // A millisecond apart, so `createdAt DESC` keeps the samples' order.
                let createdAt = now - Int64(offset)
                try ShoppingListRecord(id: list.id, name: list.name, createdAt: createdAt, updatedAt: createdAt)
                    .insert(db)
                for item in items(for: list) {
                    try ShoppingItemRecord(
                        id: item.id, listId: list.id, name: item.name, quantity: item.quantity,
                        isPickedUp: item.isPickedUp, categoryId: item.categoryId, shop: item.shop, note: item.note,
                        createdAt: createdAt, updatedAt: createdAt
                    ).insert(db)
                }
            }
        }
    }

    private static func items(for list: ShoppingListSummary) -> [ShoppingItem] {
        if list.id == ShoppingItem.sundayRoastListId { return ShoppingItem.sundayRoast }
        return (0..<list.totalItems).map { index in
            ShoppingItem(id: "\(list.id)-item-\(index)", name: "Item \(index + 1)", quantity: "1",
                         isPickedUp: index < list.pickedUpItems)
        }
    }
}

/// Sync isn't wired yet: guest writes never kick, and a dropped kick only delays a push.
struct NoOpSyncKicker: SyncKicking {
    func pushSoon() {}
}
