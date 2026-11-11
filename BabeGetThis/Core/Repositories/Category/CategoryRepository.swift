import Foundation
import GRDB

/// Domain model for a category (Android `Category`).
struct ProductCategory: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let isDefault: Bool
}

extension CategoryRecord {
    func toDomain() -> ProductCategory {
        ProductCategory(id: id, name: name, isDefault: isDefault)
    }
}

extension ProductCategory {
    func toRecord() -> CategoryRecord {
        CategoryRecord(id: id, name: name, isDefault: isDefault)
    }
}

/// Port of Android `CategoryRepository`.
struct CategoryRepository: Sendable {
    private let dao: CategoryDao
    private let safeCall: SafeCall

    init(dao: CategoryDao, safeCall: SafeCall) {
        self.dao = dao
        self.safeCall = safeCall
    }

    /// Live list of every category, alphabetical (the DAO orders by name).
    func allCategories() -> AsyncThrowingStream<[ProductCategory], any Error> {
        let values = dao.observeAllCategories().values(in: dao.writer)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await records in values {
                        continuation.yield(records.map { $0.toDomain() })
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Returns the new category's id. The name is trimmed and rejected when blank, matching the
    /// list and item repositories: this is reached from the add-item dialog's inline "new
    /// category" field, so a stray space would otherwise create a category with no visible name.
    func addCategory(name: String) async throws -> Result<String, AppError> {
        try await safeCall {
            let id = UUID().uuidString.lowercased()
            let category = ProductCategory(id: id, name: try Self.requireCategoryName(name), isDefault: false)
            try await dao.insertCategory(category.toRecord())
            return id
        }
    }

    /// The DAO's DELETE is guarded by `AND isDefault = 0`, so asking to delete a shipped default
    /// is a silent no-op that still reports success. The UI never offers it; pinned by a test.
    func deleteCategory(id: String) async throws -> Result<Void, AppError> {
        try await safeCall {
            try await dao.deleteCategory(id: id)
        }
    }

    private static func requireCategoryName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw AppErrorException(.validation("Category name can't be empty."))
        }
        return trimmed
    }
}
