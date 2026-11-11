import GRDB
import XCTest
@testable import BabeGetThis

final class CategoryDaoTests: XCTestCase {
    private var db: AppDatabase!
    private var categoryDao: CategoryDao { db.categories }

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
    }

    // Android's DEFAULT_CATEGORIES has 48 entries (the task brief's "49" miscounts).
    func testDefaultCategoriesAreSeededByTheMigration() async throws {
        let categories = try await categoryDao.allCategories()

        XCTAssertEqual(DefaultCategories.all.count, 48)
        XCTAssertEqual(categories.count, 48)
        XCTAssertEqual(Set(categories.map(\.id)), Set(DefaultCategories.all.map(\.id)))
        XCTAssertTrue(categories.allSatisfy(\.isDefault))
    }

    func testDefaultCategoryIdsAreUnique() {
        XCTAssertEqual(Set(DefaultCategories.all.map(\.id)).count, DefaultCategories.all.count)
    }

    func testAllCategoriesAreSortedByName() async throws {
        let names = try await categoryDao.allCategories().map(\.name)

        XCTAssertEqual(names, names.sorted())
        XCTAssertEqual(names.first, "Accessories & Jewelry")
    }

    // Migrating an already-migrated database must not seed again.
    func testMigratingAgainDoesNotSeedTwice() async throws {
        try await categoryDao.deleteCategory(id: "cat-other")   // ignored: a default
        try AppDatabase.migrator.migrate(db.writer)

        let count = try await categoryDao.allCategories().count
        XCTAssertEqual(count, 48)
    }

    func testInsertCategoryIgnoresAnExistingId() async throws {
        try await categoryDao.insertCategory(TestData.categoryEntity(id: "cat-other", name: "Renamed", isDefault: false))
        try await categoryDao.insertAll([
            TestData.categoryEntity(id: "cat-mine", name: "Mine", isDefault: false),
            TestData.categoryEntity(id: "cat-mine", name: "Mine again", isDefault: false),
        ])

        let categories = try await categoryDao.allCategories()
        XCTAssertEqual(categories.first { $0.id == "cat-other" }?.name, "Other")
        XCTAssertEqual(categories.first { $0.id == "cat-mine" }?.name, "Mine")
        XCTAssertEqual(categories.count, 49)
    }

    func testDeleteCategoryOnlyDeletesUserCategories() async throws {
        try await categoryDao.insertCategory(TestData.categoryEntity(id: "cat-mine", name: "Mine", isDefault: false))

        try await categoryDao.deleteCategory(id: "cat-mine")
        try await categoryDao.deleteCategory(id: "cat-dairy-eggs")

        let ids = try await categoryDao.allCategories().map(\.id)
        XCTAssertFalse(ids.contains("cat-mine"))
        XCTAssertTrue(ids.contains("cat-dairy-eggs"))
    }

    // Schema checks for migration v1.
    func testSchemaHasTheOutboxColumnsAndNoPickedUpAt() async throws {
        try await db.writer.read { db in
            let lists = try db.columns(in: "shopping_lists").map(\.name)
            let items = try db.columns(in: "shopping_items").map(\.name)
            for column in ["pendingSync", "onServer", "accountId", "deletedAt"] {
                XCTAssertTrue(lists.contains(column), column)
            }
            XCTAssertTrue(items.contains("pendingSync"))
            XCTAssertTrue(items.contains("deletedAt"))
            XCTAssertFalse(items.contains("pickedUpAt"))

            let foreignKeys = try db.foreignKeys(on: "shopping_items")
            XCTAssertEqual(foreignKeys.first?.destinationTable, "shopping_lists")
            XCTAssertEqual(foreignKeys.first?.mapping.first?.origin, "listId")
            XCTAssertTrue(try db.indexes(on: "shopping_items").contains { $0.columns == ["listId"] })
        }
    }
}
