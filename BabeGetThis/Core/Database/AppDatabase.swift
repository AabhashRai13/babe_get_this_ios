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
            // Seeded here, so exactly once per install. Raw SQL over a frozen copy:
            // a migration must not depend on CategoryRecord or DefaultCategories,
            // which keep changing. A later change to the defaults gets its own migration.
            for (id, name) in v1Categories {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO categories (id, name, isDefault) VALUES (?, ?, 1)",
                    arguments: [id, name])
            }
        }

        return migrator
    }

    /// The default categories as migration v1 seeds them (Android `DefaultCategories.kt`
    /// at DB v6). Frozen: never edit this list.
    private static let v1Categories: [(id: String, name: String)] = [
        ("cat-fruits-vegetables", "Fruits & Vegetables"),
        ("cat-dairy-eggs", "Dairy & Eggs"),
        ("cat-meat-seafood", "Meat & Seafood"),
        ("cat-bakery-bread", "Bakery & Bread"),
        ("cat-frozen-foods", "Frozen Foods"),
        ("cat-pantry-dry-goods", "Rice, Grains & Pasta"),
        ("cat-canned-jarred", "Canned & Jarred Goods"),
        ("cat-baking-supplies", "Baking & Dry Ingredients"),
        ("cat-spices-seasonings", "Spices & Seasonings"),
        ("cat-sauces-condiments", "Sauces, Condiments & Pastes"),
        ("cat-oils-vinegars", "Oils, Vinegars & Cooking Fats"),
        ("cat-breakfast-cereal", "Breakfast & Cereal"),
        ("cat-spreads", "Spreads, Honey & Jam"),
        ("cat-snacks", "Snacks"),
        ("cat-sweets-chocolate", "Sweets & Chocolate"),
        ("cat-ready-meals", "Ready Meals & Prepared Food"),
        ("cat-beverages", "Beverages"),
        ("cat-coffee-tea", "Coffee & Tea"),
        ("cat-alcohol", "Beer, Wine & Spirits"),
        ("cat-household-cleaning", "Household & Cleaning"),
        ("cat-paper-disposables", "Paper & Disposables"),
        ("cat-kitchen-dining", "Kitchen & Dining"),
        ("cat-appliances", "Appliances"),
        ("cat-furniture-storage", "Furniture & Storage"),
        ("cat-home-decor", "Home Decor"),
        ("cat-bedding-bath", "Bedding & Bath"),
        ("cat-lighting-electrical", "Lighting & Electrical"),
        ("cat-hardware-diy", "Hardware & Tools"),
        ("cat-garden-outdoor", "Garden & Outdoor"),
        ("cat-automotive", "Automotive"),
        ("cat-toiletries-personal-care", "Personal Care & Beauty"),
        ("cat-health-pharmacy", "Health & Pharmacy"),
        ("cat-clothing", "Clothing"),
        ("cat-underwear-sleepwear", "Underwear, Socks & Sleepwear"),
        ("cat-shoes", "Shoes & Footwear"),
        ("cat-accessories-jewelry", "Accessories & Jewelry"),
        ("cat-bags-luggage", "Bags & Luggage"),
        ("cat-baby-kids", "Baby & Kids"),
        ("cat-pet-supplies", "Pet Supplies"),
        ("cat-electronics", "Electronics"),
        ("cat-toys-games", "Toys & Games"),
        ("cat-books-media", "Books & Media"),
        ("cat-sports-outdoors", "Sports & Outdoors"),
        ("cat-office-stationery", "Office & Stationery"),
        ("cat-arts-crafts", "Arts, Crafts & Hobbies"),
        ("cat-party-gifts", "Party, Gifts & Holiday"),
        ("cat-tobacco-vaping", "Tobacco & Vaping"),
        ("cat-other", "Other"),
    ]
}
