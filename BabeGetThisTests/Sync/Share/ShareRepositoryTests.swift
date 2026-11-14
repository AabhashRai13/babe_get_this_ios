import Foundation
import XCTest
@testable import BabeGetThis

// Port of Android `ShareRepositoryTest` (SHARE-01, SHARE-02, SHARE-03), plus the
// two SHARE-02 code-format cases. A real in-memory database and the real
// SyncEngine, with a fake remote — like Android's InMemoryDatabaseRule setup.
final class ShareRepositoryTests: XCTestCase {
    private var db: AppDatabase!
    private var remote: ShareTestRemote!
    private var syncPoints: FakeSyncPointStore!
    private var userId: SyncTestUserId!
    private var random: ShareTestRandom!
    private var repository: ShareRepository!

    private var listDao: ShoppingListDao { db.lists }
    private var itemDao: ShoppingItemDao { db.items }

    private static let safeAlphabet = "^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$"

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
        remote = ShareTestRemote()
        syncPoints = FakeSyncPointStore()
        userId = SyncTestUserId("user-1")
        random = ShareTestRandom(seed: 7)
        let userId = userId!
        let random = random!
        let safeCall = SafeCall(reporter: SilentAppErrorReporter())
        let engine = SyncEngine(
            listDao: db.lists, itemDao: db.items, remote: remote, syncPoints: syncPoints,
            ownership: FakeListOwnershipStore(), currentUserId: { userId.value }, safeCall: safeCall)
        repository = ShareRepository(
            lists: db.lists, remote: remote, syncEngine: engine, currentUserId: { userId.value },
            safeCall: safeCall, randomIndex: { random.nextIndex($0) })
    }

    // MARK: - Helpers

    // Sharing only happens signed in, so every list here is an account list
    // (docs/technical-decisions/008); onServer says whether it has synced yet.
    private func accountList(id: String = "list-1", onServer: Bool = true, pendingSync: Bool = false) -> ShoppingListRecord {
        ShoppingListRecord(
            id: id, name: "Groceries", createdAt: 1, updatedAt: 2, isLocked: false,
            shareCode: nil, deletedAt: nil, pendingSync: pendingSync,
            accountId: "user-1", onServer: onServer)
    }

    private func localItem(_ id: String = "item-1") -> ShoppingItemRecord {
        ShoppingItemRecord(
            id: id, listId: "list-1", name: "Milk", quantity: "1", isPickedUp: false, categoryId: nil,
            shop: nil, note: nil, createdAt: 1, updatedAt: 2, deletedAt: nil, pendingSync: false)
    }

    private func data<T>(_ result: Result<T, AppError>, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("expected success, got \(error)", file: file, line: line)
            throw error
        }
    }

    private func failure<T>(_ result: Result<T, AppError>, file: StaticString = #filePath, line: UInt = #line) throws -> AppError {
        switch result {
        case .success(let value):
            XCTFail("expected an error, got \(value)", file: file, line: line)
            throw AppError.unknown()
        case .failure(let error): return error
        }
    }

    private func shareCode(_ listId: String) async throws -> String? {
        try await listDao.listRaw(id: listId)?.shareCode
    }

    // MARK: - share

    func testSharingAListAlreadyOnTheServerSetsItsCodeAndKeepsItsItems() async throws {
        try await listDao.insertList(accountList())
        try await itemDao.insertItem(localItem("item-1"))
        try await itemDao.insertItem(localItem("item-2"))

        let code = try data(await repository.share(listId: "list-1"))

        XCTAssertNotNil(code.range(of: Self.safeAlphabet, options: .regularExpression), "code from the safe alphabet")
        XCTAssertEqual(remote.shareCodeRequests.map(\.listId), ["list-1"])
        XCTAssertEqual(remote.shareCodeRequests.map(\.code), [code])
        XCTAssertTrue(remote.inner.insertedLists.isEmpty, "the row already exists")
        XCTAssertTrue(remote.inner.upsertedItems.isEmpty, "items already synced with the list")
        let stored = try await shareCode("list-1")
        XCTAssertEqual(stored, code)
        let first = try await itemDao.itemRaw(id: "item-1")
        let second = try await itemDao.itemRaw(id: "item-2")
        XCTAssertNotNil(first, "no REPLACE cascade")
        XCTAssertNotNil(second)
    }

    func testSharingAListNotYetOnTheServerPushesItFirst() async throws {
        try await listDao.insertList(accountList(onServer: false, pendingSync: true))

        let code = try data(await repository.share(listId: "list-1"))

        XCTAssertEqual(remote.inner.insertedLists.map(\.id), ["list-1"])
        XCTAssertEqual(remote.shareCodeRequests.map(\.listId), ["list-1"])
        XCTAssertEqual(remote.shareCodeRequests.map(\.code), [code])
        let onServer = try await listDao.listRaw(id: "list-1")?.onServer
        XCTAssertEqual(onServer, true)
    }

    func testSharingOfflineFailsCleanlyAndShowsNoCode() async throws {
        try await listDao.insertList(accountList(onServer: false, pendingSync: true))
        remote.inner.failUpserts = true

        let error = try failure(await repository.share(listId: "list-1"))

        XCTAssertEqual(error, .network("Couldn't share — check your connection."))
        XCTAssertTrue(remote.shareCodeRequests.isEmpty)
        let stored = try await shareCode("list-1")
        XCTAssertNil(stored)
    }

    func testWhenAnotherPhoneSharedFirstItsCodeWins() async throws {
        try await listDao.insertList(accountList())
        remote.serverShareCode = "ZZZ999"

        let code = try data(await repository.share(listId: "list-1"))

        XCTAssertEqual(code, "ZZZ999")
        let stored = try await shareCode("list-1")
        XCTAssertEqual(stored, "ZZZ999")
    }

    func testShareFailsCleanlyWhenTheServerRowCannotBeRead() async throws {
        try await listDao.insertList(accountList())
        remote.shareCodeRowMissing = true

        let error = try failure(await repository.share(listId: "list-1"))

        guard case .unknown = error else { return XCTFail("expected unknown, got \(error)") }
        let stored = try await shareCode("list-1")
        XCTAssertNil(stored)
    }

    func testShareIsIdempotentTheCodeIsStaticPerList() async throws {
        try await listDao.insertList(accountList())

        let first = try data(await repository.share(listId: "list-1"))
        let second = try data(await repository.share(listId: "list-1"))

        XCTAssertEqual(first, second)
        XCTAssertEqual(remote.shareCodeRequests.count, 1, "no second request on reopen")
    }

    func testShareRequiresSignInAndUploadsNothingWithoutIt() async throws {
        userId.value = nil
        try await listDao.insertList(accountList(onServer: false, pendingSync: true))

        let error = try failure(await repository.share(listId: "list-1"))

        guard case .auth = error else { return XCTFail("expected auth, got \(error)") }
        XCTAssertTrue(remote.inner.insertedLists.isEmpty)
        XCTAssertTrue(remote.shareCodeRequests.isEmpty)
        let stored = try await shareCode("list-1")
        XCTAssertNil(stored)
    }

    func testShareOfAMissingListIsANotFoundError() async throws {
        let error = try failure(await repository.share(listId: "ghost"))

        guard case .notFound = error else { return XCTFail("expected notFound, got \(error)") }
    }

    func testAFailedShareLeavesTheListUnsharedSoItCanBeRetried() async throws {
        try await listDao.insertList(accountList())
        remote.inner.failUpserts = true

        let result = try await repository.share(listId: "list-1")

        guard case .failure = result else { return XCTFail("expected a failure, got \(result)") }
        let stored = try await shareCode("list-1")
        XCTAssertNil(stored, "server first, local second")
    }

    // MARK: - Code format (SHARE-02)

    func testCodesAreSixCharactersDrawnFromTheInjectedRandomSource() async throws {
        let expectedRandom = ShareTestRandom(seed: 7)
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let expected = String((0..<6).map { _ in alphabet[expectedRandom.nextIndex(alphabet.count)] })
        try await listDao.insertList(accountList())

        let code = try data(await repository.share(listId: "list-1"))

        XCTAssertEqual(code, expected)
        XCTAssertNil(code.rangeOfCharacter(from: CharacterSet(charactersIn: "0O1I")), "no ambiguous characters")
    }

    func testAUniqueConstraintClashFailsTheCallAndARetryGeneratesANewCode() async throws {
        try await listDao.insertList(accountList())
        remote.shareCodeClashes = 1

        let failed = try await repository.share(listId: "list-1")
        // Android: the 409 RestException goes through onClientError to AuthError("Request failed.").
        XCTAssertEqual(try failure(failed), .auth("Request failed."))
        let afterClash = try await shareCode("list-1")
        XCTAssertNil(afterClash)

        let code = try data(await repository.share(listId: "list-1"))

        XCTAssertEqual(remote.shareCodeRequests.count, 2)
        XCTAssertNotEqual(remote.shareCodeRequests[0].code, remote.shareCodeRequests[1].code, "a fresh code")
        XCTAssertEqual(code, remote.shareCodeRequests[1].code)
        let stored = try await shareCode("list-1")
        XCTAssertEqual(stored, code)
    }

    // MARK: - join

    func testJoinTrimsTheCodeBecomesAMemberAndLandsTheReplicaInTheDatabase() async throws {
        remote.inner.joinResult = "list-9"
        remote.inner.listRows = [
            ListRow(id: "list-9", name: "Their list", shareCode: "ABC234", updatedAt: "2026-08-01T10:00:00Z"),
        ]
        remote.inner.itemRows = [
            ItemRow(id: "item-9", listId: "list-9", name: "Milk", quantity: "1", updatedAt: "2026-08-01T10:00:00Z"),
        ]

        let listId = try data(await repository.join(code: "  abc234  "))

        XCTAssertEqual(listId, "list-9")
        XCTAssertEqual(remote.inner.joinCalledWith, "abc234")
        let list = try await listDao.listRaw(id: "list-9")
        XCTAssertEqual(list?.name, "Their list")
        let item = try await itemDao.itemRaw(id: "item-9")
        XCTAssertEqual(item?.name, "Milk")
    }

    func testReJoinRefreshesTheReplicaInsteadOfNoOpingFromACurrentSyncPoint() async throws {
        // Already a member with an already-current high-water mark — the exact
        // state where plain catchUp fetches nothing (BUG 2 from device testing).
        remote.inner.joinResult = "list-9"
        syncPoints.set(listId: "list-9", iso: "2026-08-08T12:00:00Z")
        remote.inner.listRows = [
            ListRow(id: "list-9", name: "Their list", shareCode: "ABC234", updatedAt: "2026-08-01T10:00:00Z"),
        ]

        _ = try await repository.join(code: "ABC234")

        XCTAssertEqual(remote.inner.fetchedListIds, ["list-9"])
        XCTAssertNil(remote.inner.lastListSince, "full pull — the stored mark must not gate the fetch")
        let list = try await listDao.listRaw(id: "list-9")
        XCTAssertEqual(list?.name, "Their list")
    }

    func testJoinWithAnUnknownCodeIsANotFoundError() async throws {
        remote.inner.joinResult = nil

        let error = try failure(await repository.join(code: "XXXXXX"))

        XCTAssertEqual(error, .notFound("That code didn't match any list."))
    }

    func testJoinSurfacesAFailedInitialPull() async throws {
        remote.inner.joinResult = "list-9"
        remote.inner.failFetches = true

        let result = try await repository.join(code: "ABC234")

        guard case .failure = result else { return XCTFail("expected a failure, got \(result)") }
    }
}
