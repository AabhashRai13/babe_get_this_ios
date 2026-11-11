import XCTest
@testable import BabeGetThis

final class PagingTests: XCTestCase {
    private struct PagedRow: Equatable {
        let updatedAt: String
        let id: String
    }

    private static func cursor(_ row: PagedRow) -> SharedListPageCursor {
        SharedListPageCursor(updatedAt: row.updatedAt, id: row.id)
    }

    private static func rows(_ ids: ClosedRange<Int>) -> [PagedRow] {
        ids.map { PagedRow(updatedAt: "2026-11-12T10:00:00.000000+00:00", id: String(format: "id-%04d", $0)) }
    }

    override func setUp() {
        super.setUp()
        SharedListURLStub.reset()
    }

    func testKeysetPagingStopsAtTheFirstShortPage() async throws {
        var cursors: [SharedListPageCursor?] = []
        let pages = [Self.rows(1...3), Self.rows(4...6), Self.rows(7...8), Self.rows(9...12)]

        let all = try await SharedListPaging.fetchAll(pageSize: 3, cursorOf: Self.cursor) { cursor in
            cursors.append(cursor)
            return pages[cursors.count - 1]
        }

        XCTAssertEqual(all, Self.rows(1...8), "the short third page ends paging; the fourth is never requested")
        XCTAssertEqual(cursors, [
            nil,
            SharedListPageCursor(updatedAt: "2026-11-12T10:00:00.000000+00:00", id: "id-0003"),
            SharedListPageCursor(updatedAt: "2026-11-12T10:00:00.000000+00:00", id: "id-0006"),
        ])
    }

    func testAFullLastPageCostsOneMoreEmptyRequest() async throws {
        var calls = 0
        let all = try await SharedListPaging.fetchAll(pageSize: 2, cursorOf: Self.cursor) { _ in
            calls += 1
            return calls == 1 ? Self.rows(1...2) : []
        }

        XCTAssertEqual(all, Self.rows(1...2))
        XCTAssertEqual(calls, 2)
    }

    func testEmptyFirstPageReturnsNothingAfterOneRequest() async throws {
        var calls = 0
        let all: [PagedRow] = try await SharedListPaging.fetchAll(pageSize: 2, cursorOf: Self.cursor) { _ in
            calls += 1
            return []
        }

        XCTAssertEqual(all, [])
        XCTAssertEqual(calls, 1)
    }

    func testPageSizeIsPostgrestDefaultMaxRows() {
        XCTAssertEqual(SharedListPaging.pageSize, 1000)
    }

    func testAfterFilterIsStrictlyAfterTheCursorInUpdatedAtThenIdOrder() {
        let filter = SharedListPaging.afterFilter(
            SharedListPageCursor(updatedAt: "2026-11-12T10:00:00.5+00:00", id: "abc")
        )
        XCTAssertEqual(
            filter,
            #"updated_at.gt."2026-11-12T10:00:00.5+00:00",and(updated_at.eq."2026-11-12T10:00:00.5+00:00",id.gt."abc")"#
        )
    }

    func testFetchAllListsPagesThroughTheServerWithAKeysetCursor() async throws {
        let stamp = "2026-11-12T10:00:00.123456+00:00"
        let fullPage = (1...SharedListPaging.pageSize).map {
            #"{"id":"l\#($0)","name":"List","updated_at":"\#(stamp)"}"#
        }
        SharedListURLStub.enqueue(.init(json: "[" + fullPage.joined(separator: ",") + "]"))
        SharedListURLStub.enqueue(.init(json: #"[{"id":"zz","name":"Last","updated_at":"2026-11-12T11:00:00+00:00"}]"#))
        let remote = SupabaseSharedListRemote(client: SharedListURLStub.makeClient())

        let lists = try await remote.fetchAllLists()

        XCTAssertEqual(lists.count, SharedListPaging.pageSize + 1)
        XCTAssertEqual(lists.last?.id, "zz")
        let requests = SharedListURLStub.requests
        XCTAssertEqual(requests.count, 2, "the short second page ends paging")
        for request in requests {
            XCTAssertEqual(request.method, "GET")
            XCTAssertEqual(request.path, "/rest/v1/lists")
            XCTAssertEqual(request.query("order"), ["updated_at.asc.nullslast,id.asc.nullslast"])
            XCTAssertEqual(request.query("limit"), ["1000"])
        }
        XCTAssertEqual(requests[0].query("or"), [], "the first page has no cursor")
        XCTAssertEqual(
            requests[1].query("or"),
            [#"(updated_at.gt."\#(stamp)",and(updated_at.eq."\#(stamp)",id.gt."l1000"))"#]
        )
        XCTAssertTrue(
            requests[1].request.url?.absoluteString.contains("%2B00%3A00") == true,
            "+ in the timestamp is percent-encoded, so PostgREST doesn't read it as a space"
        )
    }
}
