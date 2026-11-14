import XCTest
@testable import BabeGetThis

/// Both voice entry points save every spoken draft, empty quantity included (Android
/// `draftsToItems`: `quantity.orEmpty()`). Real in-memory database; no network, no microphone.
final class VoiceListSaveTests: XCTestCase {
    private var db: AppDatabase!
    private var repository: ShoppingListRepository!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        repository = ShoppingListRepository(
            listDao: db.lists,
            itemDao: db.items,
            categoryDao: db.categories,
            authStateManager: authStateFor(nil),
            syncKicker: CountingSyncKicker(),
            safeCall: SafeCall(reporter: SilentAppErrorReporter()))
    }

    /// "milk, eggs, bread": no quantities.
    private var spoken: [ItemDraft] {
        ["Milk", "Eggs", "Bread"].map { TestData.draft(name: $0, quantity: nil) }
    }

    func testSpokenItemsWithoutQuantityAreAllSaved() async throws {
        let drafts = spoken
        XCTAssertTrue(drafts.allSatisfy { $0.quantity.isEmpty && $0.isSavableVoiceItem })

        // Create by voice (Lists screen): a new list with three items.
        let created = try await repository.createListWithItems(name: autoNameVoiceList(drafts), drafts: drafts)
        guard case .success(let newId) = created else { return XCTFail("create failed: \(created)") }
        let createdItems = try await db.items.itemsByListIdOnce(newId)
        XCTAssertEqual(["Bread", "Eggs", "Milk"], createdItems.map(\.name).sorted())
        XCTAssertTrue(createdItems.allSatisfy { $0.quantity.isEmpty })

        // Mic inside an existing list: three items saved straight into it.
        let existing = try await repository.createList(name: "Groceries")
        guard case .success(let listId) = existing else { return XCTFail("create failed: \(existing)") }
        let saved = await saveVoiceDrafts(drafts, intoList: listId, using: repository)
        XCTAssertEqual(.success(listId), saved)
        let items = try await db.items.itemsByListIdOnce(listId)
        XCTAssertEqual(["Bread", "Eggs", "Milk"], items.map(\.name).sorted())
        XCTAssertTrue(items.allSatisfy { $0.quantity.isEmpty })
    }

    func testAppendedItemsKeepWhatWasAlreadyInTheList() async throws {
        guard case .success(let listId) = try await repository.createList(name: "Groceries") else {
            return XCTFail("create failed")
        }
        try await db.items.insertItem(TestData.itemEntity(id: "existing", listId: listId))

        _ = await saveVoiceDrafts(spoken, intoList: listId, using: repository)

        let count = try await db.items.itemsByListIdOnce(listId).count
        XCTAssertEqual(4, count)
    }

    func testAFailedSaveSurfacesTheRepositoryMessage() async {
        let result = await saveVoiceDrafts(spoken, intoList: "x", using: FailingAdder())

        XCTAssertEqual(.failure(.unknown("disk full")), result)
    }

    func testAThrownSaveBecomesTheDefaultUnknownError() async {
        let result = await saveVoiceDrafts(spoken, intoList: "x", using: ThrowingAdder())

        XCTAssertEqual(.failure(.unknown()), result)
    }
}

private struct FailingAdder: ListItemsAdding {
    func addItemsToList(listId: String, drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        .failure(.unknown("disk full"))
    }
}

private struct ThrowingAdder: ListItemsAdding {
    func addItemsToList(listId: String, drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        throw CancellationError()
    }
}
