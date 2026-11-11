import GRDB

// Port of Android `CategoryDao`.
struct CategoryDao: Sendable {
    let writer: any DatabaseWriter

    func allCategories() async throws -> [CategoryRecord] {
        try await writer.read { db in try Self.fetchAll(db) }
    }

    /// Live version of `allCategories()`.
    func observeAllCategories() -> ValueObservation<ValueReducers.Fetch<[CategoryRecord]>> {
        ValueObservation.tracking { db in try Self.fetchAll(db) }
    }

    /// Ignores an id that already exists.
    func insertCategory(_ category: CategoryRecord) async throws {
        try await writer.write { db in try category.insert(db, onConflict: .ignore) }
    }

    func insertAll(_ categories: [CategoryRecord]) async throws {
        try await writer.write { db in
            for category in categories { try category.insert(db, onConflict: .ignore) }
        }
    }

    /// Only user-created categories can be deleted.
    func deleteCategory(id: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM categories WHERE id = ? AND isDefault = 0", arguments: [id])
        }
    }

    private static func fetchAll(_ db: Database) throws -> [CategoryRecord] {
        try CategoryRecord.fetchAll(db, sql: "SELECT * FROM categories ORDER BY name ASC")
    }
}
