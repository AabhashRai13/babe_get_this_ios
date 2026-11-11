import Foundation
import GRDB

// The local SQLite database: owns the writer and the schema migrations, and
// hands out the DAOs. GRDB turns foreign keys on by default, so the CASCADE
// from shopping_items to shopping_lists is enforced.
struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// For tests and previews.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    /// The app's on-disk database in Application Support.
    static func onDisk(fileName: String = "babegetthis.sqlite") throws -> AppDatabase {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try AppDatabase(DatabasePool(path: folder.appendingPathComponent(fileName).path))
    }

    var lists: ShoppingListDao { ShoppingListDao(writer: writer) }
    var items: ShoppingItemDao { ShoppingItemDao(writer: writer) }
    var categories: CategoryDao { CategoryDao(writer: writer) }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // v1 = the Android schema at DB v6 minus pickedUpAt and the Got This tables.
        migrator.registerMigration("v1") { db in
            try db.create(table: "shopping_lists") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("isLocked", .boolean).notNull().defaults(to: false)
                t.column("shareCode", .text)
                t.column("deletedAt", .integer)
                t.column("pendingSync", .boolean).notNull().defaults(to: false)
                t.column("accountId", .text)
                t.column("onServer", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "shopping_items") { t in
                t.primaryKey("id", .text)
                t.column("listId", .text).notNull()
                    .references("shopping_lists", column: "id", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("quantity", .text).notNull()
                t.column("isPickedUp", .boolean).notNull().defaults(to: false)
                t.column("categoryId", .text)
                t.column("shop", .text)
                t.column("note", .text)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("deletedAt", .integer)
                t.column("pendingSync", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "index_shopping_items_listId", on: "shopping_items", columns: ["listId"])
            try db.create(table: "categories") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("isDefault", .boolean).notNull()
            }
            // Seeded here, so exactly once per install.
            for category in DefaultCategories.all {
                try category.insert(db, onConflict: .ignore)
            }
        }

        return migrator
    }
}
