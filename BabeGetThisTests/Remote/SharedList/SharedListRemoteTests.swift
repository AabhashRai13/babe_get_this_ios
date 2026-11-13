import Supabase
import XCTest
@testable import BabeGetThis

final class SharedListRemoteTests: XCTestCase {
    private var remote: SupabaseSharedListRemote!

    private let list = ListRow(id: "list-1", name: "Groceries", createdBy: "user-1", createdAt: "2026-11-12T09:00:00Z")
    private let item = ItemRow(id: "item-1", listId: "list-1", name: "Milk", quantity: "2", isPickedUp: true)

    override func setUp() {
        super.setUp()
        SharedListURLStub.reset()
        remote = SupabaseSharedListRemote(client: SharedListURLStub.makeClient())
    }

    override func tearDown() {
        remote = nil
        SharedListURLStub.reset()
        super.tearDown()
    }

    private func onlyRequest(file: StaticString = #filePath, line: UInt = #line) throws -> SharedListURLStub.Captured {
        let requests = SharedListURLStub.requests
        XCTAssertEqual(requests.count, 1, file: file, line: line)
        return try XCTUnwrap(requests.first, file: file, line: line)
    }

    private func jsonObject(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - insertList (first push)

    func testInsertListIsAPlainInsertNotAnUpsert() async throws {
        SharedListURLStub.enqueue(.init(status: 201, json: ""))

        let inserted = try await remote.insertList(list)

        XCTAssertTrue(inserted)
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/lists")
        XCTAssertFalse(request.header("Prefer")?.contains("resolution=") == true, "an upsert fails RLS 42501")
        XCTAssertEqual(request.query("on_conflict"), [])
        let body = try XCTUnwrap(try jsonObject(request.body) as? [String: Any])
        XCTAssertEqual(body["id"] as? String, "list-1")
        XCTAssertEqual(body["name"] as? String, "Groceries")
        XCTAssertEqual(body["created_by"] as? String, "user-1")
    }

    func testDuplicateInsertReturnsFalse() async throws {
        SharedListURLStub.enqueue(.init(status: 409, json: """
        {"code":"23505","details":"Key (id)=(list-1) already exists.","hint":null,\
        "message":"duplicate key value violates unique constraint \\"lists_pkey\\""}
        """))

        let inserted = try await remote.insertList(list)

        XCTAssertFalse(inserted)
    }

    func testDuplicateKeyMessageWithoutACodeAlsoReturnsFalse() async throws {
        SharedListURLStub.enqueue(.init(status: 409, json: """
        {"message":"duplicate key value violates unique constraint \\"lists_share_code_key\\""}
        """))

        let inserted = try await remote.insertList(list)

        XCTAssertFalse(inserted)
    }

    func testInsertRlsFailureIsThrownNotSwallowed() async throws {
        SharedListURLStub.enqueue(.init(status: 403, json: """
        {"code":"42501","message":"new row violates row-level security policy for table \\"lists\\""}
        """))

        do {
            _ = try await remote.insertList(list)
            XCTFail("expected a throw")
        } catch let error as PostgrestError {
            XCTAssertEqual(error.code, "42501")
        }
    }

    // MARK: - setShareCode

    func testSetShareCodeIsATargetedUpdateReturningTheServersCode() async throws {
        SharedListURLStub.enqueue(.init(json: """
        [{"id":"list-1","name":"Groceries","share_code":"FIRST2","updated_at":"2026-11-12T10:00:00+00:00"}]
        """))

        let code = try await remote.setShareCode(listId: "list-1", code: "ABC234")

        XCTAssertEqual(code, "FIRST2", "the server's write-once trigger keeps the first code")
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.path, "/rest/v1/lists")
        XCTAssertEqual(request.query("id"), ["eq.list-1"])
        XCTAssertTrue(request.header("Prefer")?.contains("return=representation") == true)
        let body = try XCTUnwrap(try jsonObject(request.body) as? [String: String])
        XCTAssertEqual(body, ["share_code": "ABC234"], "never the whole row")
    }

    func testSetShareCodeReturnsNilWhenTheRowIsNotVisible() async throws {
        SharedListURLStub.enqueue(.init(json: "[]"))

        let code = try await remote.setShareCode(listId: "list-1", code: "ABC234")

        XCTAssertNil(code)
    }

    // MARK: - upserts

    func testUpsertListsMergesDuplicates() async throws {
        SharedListURLStub.enqueue(.init(status: 201, json: ""))

        try await remote.upsertLists([list, ListRow(id: "list-2", name: "Hardware")])

        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/lists")
        XCTAssertTrue(request.header("Prefer")?.contains("resolution=merge-duplicates") == true)
        let body = try XCTUnwrap(try jsonObject(request.body) as? [[String: Any]])
        XCTAssertEqual(body.map { $0["id"] as? String }, ["list-1", "list-2"])
    }

    func testUpsertItemsNeverSendsPickedUpAt() async throws {
        SharedListURLStub.enqueue(.init(status: 201, json: ""))

        try await remote.upsertItems([item])

        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/items")
        XCTAssertTrue(request.header("Prefer")?.contains("resolution=merge-duplicates") == true)
        XCTAssertFalse(request.bodyString.contains("picked_up_at"), "iOS v1 acts as a pre-Got-This client")
        let body = try XCTUnwrap(try jsonObject(request.body) as? [[String: Any]])
        XCTAssertEqual(body.first?["list_id"] as? String, "list-1")
        XCTAssertEqual(body.first?["is_picked_up"] as? Bool, true)
    }

    // MARK: - fetches

    func testFetchListFiltersByIdAndSinceWithGte() async throws {
        SharedListURLStub.enqueue(.init(json: """
        [{"id":"list-1","name":"Groceries","updated_at":"2026-11-12T10:00:00+00:00"}]
        """))

        let rows = try await remote.fetchList(listId: "list-1", sinceIso: "2026-11-12T09:00:00+00:00")

        XCTAssertEqual(rows.map(\.id), ["list-1"])
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/rest/v1/lists")
        XCTAssertEqual(request.query("id"), ["eq.list-1"])
        XCTAssertEqual(request.query("updated_at"), ["gte.2026-11-12T09:00:00+00:00"])
    }

    func testFetchListWithoutSinceIsAFullPull() async throws {
        SharedListURLStub.enqueue(.init(json: "[]"))

        let rows = try await remote.fetchList(listId: "list-1", sinceIso: nil)

        XCTAssertEqual(rows, [])
        XCTAssertEqual(try onlyRequest().query("updated_at"), [])
    }

    func testFetchItemsFiltersByListAndSinceAndIsPaged() async throws {
        SharedListURLStub.enqueue(.init(json: """
        [{"id":"item-1","list_id":"list-1","name":"Milk","quantity":"1","is_picked_up":false,\
        "picked_up_at":"2026-11-12T10:00:00+00:00","updated_at":"2026-11-12T10:00:00+00:00"}]
        """))

        let rows = try await remote.fetchItems(listId: "list-1", sinceIso: "2026-11-12T09:00:00+00:00")

        XCTAssertEqual(rows.map(\.id), ["item-1"], "picked_up_at on a read row is ignored")
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/items")
        XCTAssertEqual(request.query("list_id"), ["eq.list-1"])
        XCTAssertEqual(request.query("updated_at"), ["gte.2026-11-12T09:00:00+00:00"])
        XCTAssertEqual(request.query("order"), ["updated_at.asc.nullslast,id.asc.nullslast"])
        XCTAssertEqual(request.query("limit"), ["1000"])
    }

    func testFetchAccountItemsHasNoListFilter() async throws {
        SharedListURLStub.enqueue(.init(json: "[]"))

        let rows = try await remote.fetchAccountItems(sinceIso: nil)

        XCTAssertEqual(rows, [])
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/items")
        XCTAssertEqual(request.query("list_id"), [], "RLS scopes it to the account's lists")
        XCTAssertEqual(request.query("updated_at"), [])
        XCTAssertEqual(request.query("limit"), ["1000"])
    }

    func testFetchAccountItemsSinceUsesGte() async throws {
        SharedListURLStub.enqueue(.init(json: "[]"))

        _ = try await remote.fetchAccountItems(sinceIso: "2026-11-12T09:00:00+00:00")

        XCTAssertEqual(try onlyRequest().query("updated_at"), ["gte.2026-11-12T09:00:00+00:00"])
    }

    func testFetchAllListsHasNoSinceFilter() async throws {
        SharedListURLStub.enqueue(.init(json: """
        [{"id":"list-1","name":"Groceries","share_code":"ABC234","updated_at":"2026-11-12T10:00:00+00:00"}]
        """))

        let rows = try await remote.fetchAllLists()

        XCTAssertEqual(rows.map(\.shareCode), ["ABC234"])
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/lists")
        XCTAssertEqual(request.query("updated_at"), [], "membership changes don't bump updated_at")
    }

    // MARK: - joinListByCode

    func testJoinListByCodeCallsTheRpcAndReturnsTheListId() async throws {
        SharedListURLStub.enqueue(.init(json: #""list-9""#))

        let listId = try await remote.joinListByCode("ABC234")

        XCTAssertEqual(listId, "list-9")
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/join_list_by_code")
        let body = try XCTUnwrap(try jsonObject(request.body) as? [String: String])
        XCTAssertEqual(body, ["p_code": "ABC234"])
    }

    func testJoinListByCodeReturnsNilForAnInvalidCode() async throws {
        SharedListURLStub.enqueue(.init(status: 400, json: #"{"code":"P0001","message":"invalid_code"}"#))

        let listId = try await remote.joinListByCode("ZZZZZZ")

        XCTAssertNil(listId)
    }

    func testJoinListByCodeThrowsOtherFailures() async throws {
        SharedListURLStub.enqueue(.init(status: 401, json: #"{"code":"PGRST301","message":"JWT expired"}"#))

        do {
            _ = try await remote.joinListByCode("ABC234")
            XCTFail("expected a throw")
        } catch let error as PostgrestError {
            XCTAssertEqual(error.code, "PGRST301")
        }
    }

    // MARK: - duplicate detection

    // MARK: - changes (realtime)

    func testEachSubscriptionGetsItsOwnTopic() {
        let first = SupabaseSharedListRemote.channelTopic(listId: "list-1")
        let second = SupabaseSharedListRemote.channelTopic(listId: "list-1")

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasPrefix("list-list-1-"))
    }

    // Close a list screen and reopen it at once: the old channel is still being removed when
    // the new subscription creates its channel. The new one must be a different channel and
    // must stay registered after the old removal completes.
    func testRestartingASubscriptionWhileTheOldChannelIsRemovedKeepsTheNewChannel() async {
        let client = SharedListURLStub.makeClient()
        let old = client.channel(SupabaseSharedListRemote.channelTopic(listId: "list-1"))
        let removal = Task { await client.removeChannel(old) }

        let new = client.channel(SupabaseSharedListRemote.channelTopic(listId: "list-1"))
        await removal.value

        XCTAssertFalse(old === new)
        XCTAssertTrue(client.realtimeV2.channels[new.topic] === new)
        XCTAssertNil(client.realtimeV2.channels[old.topic])
        await client.removeChannel(new)
    }

    // Why a fixed topic was unsafe: the client hands back the registered channel for a topic.
    func testAFixedTopicWouldReuseTheRegisteredChannel() async {
        let client = SharedListURLStub.makeClient()
        let first = client.channel("list-1")
        XCTAssertTrue(client.channel("list-1") === first)
        await client.removeChannel(first)
    }

    func testIsDuplicateMatchesCodeOrMessage() {
        XCTAssertTrue(SupabaseSharedListRemote.isDuplicate(PostgrestError(code: "23505", message: "x")))
        XCTAssertTrue(SupabaseSharedListRemote.isDuplicate(PostgrestError(message: "ERROR 23505")))
        XCTAssertTrue(SupabaseSharedListRemote.isDuplicate(PostgrestError(message: "duplicate key value")))
        XCTAssertFalse(SupabaseSharedListRemote.isDuplicate(PostgrestError(code: "42501", message: "rls")))
    }
}
