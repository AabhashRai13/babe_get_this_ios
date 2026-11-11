import GRDB
import XCTest
@testable import BabeGetThis

/// Port of Android's CategoryDataTest. The iOS migration seeds the 48 defaults, while Android's
/// in-memory test database starts empty, so setUp clears the table to match the Android fixture.
final class CategoryRepositoryTests: XCTestCase {
    private var db: AppDatabase!
    private var dao: CategoryDao { db.categories }
    private var repository: CategoryRepository!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        try await db.writer.write { try $0.execute(sql: "DELETE FROM categories") }
        repository = CategoryRepository(dao: db.categories, safeCall: SafeCall(reporter: SilentAppErrorReporter()))
    }

    private func current() async throws -> [ProductCategory] {
        var iterator = repository.allCategories().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    private func daoNames() async throws -> [String] {
        try await dao.allCategories().map(\.name)
    }

    private func data<T>(_ result: Result<T, AppError>, line: UInt = #line) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("expected success, got \(error)", line: line)
            throw error
        }
    }

    private func error<T>(_ result: Result<T, AppError>) -> AppError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    // MARK: - mappers

    func testRecordToDomainCarriesEveryField() {
        let domain = TestData.categoryEntity(id: "c1", name: "Dairy", isDefault: true).toDomain()

        XCTAssertEqual("c1", domain.id)
        XCTAssertEqual("Dairy", domain.name)
        XCTAssertTrue(domain.isDefault)
    }

    func testAUserCreatedCategoryMapsAsNotDefault() {
        XCTAssertFalse(TestData.categoryEntity(isDefault: false).toDomain().isDefault)
    }

    func testToRecordRoundTrips() {
        let record = TestData.categoryEntity(id: "c9", name: "Bakery", isDefault: false)

        XCTAssertEqual(record, record.toDomain().toRecord())
    }

    // MARK: - DAO

    func testCategoriesComeBackInAlphabeticalOrder() async throws {
        try await dao.insertCategory(TestData.categoryEntity(id: "c1", name: "Zucchini"))
        try await dao.insertCategory(TestData.categoryEntity(id: "c2", name: "Apples"))
        try await dao.insertCategory(TestData.categoryEntity(id: "c3", name: "Milk"))

        let names = try await daoNames()

        XCTAssertEqual(["Apples", "Milk", "Zucchini"], names)
    }

    // IGNORE, not REPLACE: re-seeding defaults must not clobber a row the user has interacted with.
    func testInsertingAConflictingIdIsIgnoredRatherThanReplacing() async throws {
        try await dao.insertCategory(TestData.categoryEntity(id: "c1", name: "First"))
        try await dao.insertCategory(TestData.categoryEntity(id: "c1", name: "Second"))

        let stored = try await dao.allCategories()
        XCTAssertEqual(1, stored.count)
        XCTAssertEqual("First", stored.first?.name)
    }

    func testInsertAllSeedsManyAtOnce() async throws {
        try await dao.insertAll(DefaultCategories.all)

        let count = try await dao.allCategories().count
        XCTAssertEqual(DefaultCategories.all.count, count)
    }

    func testSeedingTwiceDoesNotDuplicate() async throws {
        try await dao.insertAll(DefaultCategories.all)
        try await dao.insertAll(DefaultCategories.all)

        let count = try await dao.allCategories().count
        XCTAssertEqual(DefaultCategories.all.count, count)
    }

    func testAUserCategoryCanBeDeleted() async throws {
        try await dao.insertCategory(TestData.categoryEntity(id: "c1", isDefault: false))

        try await dao.deleteCategory(id: "c1")

        let stored = try await dao.allCategories()
        XCTAssertTrue(stored.isEmpty)
    }

    // The DELETE is guarded by `AND isDefault = 0`, so a shipped default is protected in SQL.
    func testADefaultCategoryCannotBeDeleted() async throws {
        try await dao.insertCategory(TestData.categoryEntity(id: "c1", isDefault: true))

        try await dao.deleteCategory(id: "c1")

        let count = try await dao.allCategories().count
        XCTAssertEqual(1, count)
    }

    // MARK: - repository

    func testAddCategoryStoresItAndReturnsTheNewId() async throws {
        let id = try data(try await repository.addCategory(name: "Dairy"))

        let stored = try await current()
        XCTAssertEqual(1, stored.count)
        XCTAssertEqual(id, stored.first?.id)
        XCTAssertEqual("Dairy", stored.first?.name)
        XCTAssertEqual(false, stored.first?.isDefault, "user-created categories are never default")
    }

    func testAddCategoryTrimsTheName() async throws {
        _ = try await repository.addCategory(name: "  Dairy  ")

        let stored = try await current()
        XCTAssertEqual("Dairy", stored.first?.name)
    }

    func testAddCategoryRejectsABlankName() async throws {
        let result = try await repository.addCategory(name: "   ")

        guard case .validation = error(result) else { return XCTFail("got \(result)") }
        let stored = try await current()
        XCTAssertTrue(stored.isEmpty)
    }

    func testAddCategoryRejectsAnEmptyName() async throws {
        let result = try await repository.addCategory(name: "")

        XCTAssertEqual(.validation("Category name can't be empty."), error(result))
    }

    func testTwoCategoriesMayShareAName() async throws {
        // Nothing enforces uniqueness; ids differ. Pinned so a future unique constraint is deliberate.
        _ = try await repository.addCategory(name: "Dairy")
        _ = try await repository.addCategory(name: "Dairy")

        let stored = try await current()
        XCTAssertEqual(2, stored.count)
    }

    func testAllCategoriesIsEmptyToStart() async throws {
        let stored = try await current()
        XCTAssertTrue(stored.isEmpty)
    }

    func testDeleteCategoryRemovesAUserCategory() async throws {
        let id = try data(try await repository.addCategory(name: "Dairy"))

        _ = try await repository.deleteCategory(id: id)

        let stored = try await current()
        XCTAssertTrue(stored.isEmpty)
    }

    // Latent inconsistency, pinned: the DAO refuses to delete a default, but the repository
    // still reports success, so a caller cannot tell nothing happened.
    func testDeletingADefaultReportsSuccessEvenThoughNothingIsRemoved() async throws {
        try await dao.insertCategory(TestData.categoryEntity(id: "c1", isDefault: true))

        let result = try await repository.deleteCategory(id: "c1")

        guard case .success = result else { return XCTFail("got \(result)") }
        let stored = try await current()
        XCTAssertEqual(1, stored.count)
    }

    func testDeletingAnIdThatDoesNotExistAlsoReportsSuccess() async throws {
        let result = try await repository.deleteCategory(id: "nope")

        guard case .success = result else { return XCTFail("got \(result)") }
    }

    func testTheObservationEmitsWhenACategoryIsAdded() async throws {
        var iterator = repository.allCategories().makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual([], first)

        _ = try await repository.addCategory(name: "Dairy")

        let second = try await iterator.next()
        XCTAssertEqual(["Dairy"], second?.map(\.name))
    }

    // MARK: - DefaultCategories

    func testTheSeedSetIsNotEmpty() {
        XCTAssertFalse(DefaultCategories.all.isEmpty)
    }

    // Fixed ids, so they stay stable across installs: voice transcription maps backend
    // category slugs onto exactly these.
    func testSeedIdsAreUnique() {
        XCTAssertEqual(DefaultCategories.all.count, Set(DefaultCategories.all.map(\.id)).count)
    }

    func testSeedNamesAreUnique() {
        XCTAssertEqual(DefaultCategories.all.count, Set(DefaultCategories.all.map(\.name)).count)
    }

    func testEverySeedEntryIsFlaggedDefault() {
        XCTAssertTrue(DefaultCategories.all.allSatisfy(\.isDefault))
    }

    func testNoSeedEntryHasABlankNameOrId() {
        let blank = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        XCTAssertTrue(DefaultCategories.all.allSatisfy { !blank($0.id) && !blank($0.name) })
    }
}
