import Foundation
import GRDB

/// Writes `ShoppingListSummary.samples` into a database as guest lists, so `-sampleData`
/// and previews run the real repository path. Each list gets placeholder items, the
/// first `pickedUpItems` of them picked up.
enum SampleListSeeder {
    static func seed(_ database: AppDatabase, lists: [ShoppingListSummary] = ShoppingListSummary.samples) throws {
        let now = Int64((Date().timeIntervalSince1970 * 1000).rounded())
        try database.writer.write { db in
            for (offset, list) in lists.enumerated() {
                // A millisecond apart, so `createdAt DESC` keeps the samples' order.
                let createdAt = now - Int64(offset)
                try ShoppingListRecord(id: list.id, name: list.name, createdAt: createdAt, updatedAt: createdAt)
                    .insert(db)
                for index in 0..<list.totalItems {
                    try ShoppingItemRecord(
                        id: "\(list.id)-item-\(index)", listId: list.id, name: "Item \(index + 1)", quantity: "1",
                        isPickedUp: index < list.pickedUpItems, createdAt: createdAt, updatedAt: createdAt
                    ).insert(db)
                }
            }
        }
    }
}

/// Sync isn't wired yet: guest writes never kick, and a dropped kick only delays a push.
struct NoOpSyncKicker: SyncKicking {
    func pushSoon() {}
}
