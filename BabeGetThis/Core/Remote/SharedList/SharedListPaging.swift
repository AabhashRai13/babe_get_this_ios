import Foundation

/// The last row of a page: everything strictly after it, in `(updated_at, id)` order, is the next page.
struct SharedListPageCursor: Equatable, Sendable {
    let updatedAt: String?
    let id: String
}

/// Port of Android `core/sync/data/remote/Paging.kt`.
enum SharedListPaging {
    /// Rows per request. Equal to Supabase's default PostgREST max_rows so a full page is exactly one
    /// request; it must never be set above the project's max_rows (see `fetchAll`).
    static let pageSize = 1000

    /// The whole result, a page at a time. Keyset paging on (updated_at, id) rather than offsets: a row
    /// updated while paging moves to the end of the order, and with offsets that shifts every row behind it
    /// by one — the one that slips across the page boundary is never returned. With a cursor the moved row
    /// simply shows up in a later page (or the next pass).
    /// Stops at the first short page; a page the server cut short at max_rows would look complete, so
    /// `pageSize` must not exceed it.
    static func fetchAll<Row>(
        pageSize: Int = SharedListPaging.pageSize,
        cursorOf: (Row) -> SharedListPageCursor,
        fetchPage: (SharedListPageCursor?) async throws -> [Row]
    ) async throws -> [Row] {
        var rows: [Row] = []
        var after: SharedListPageCursor?
        while true {
            let page = try await fetchPage(after)
            rows += page
            guard page.count >= pageSize, let last = page.last else { return rows }
            after = cursorOf(last)
        }
    }

    /// PostgREST `or` filter selecting everything strictly after `cursor`, in the order rows are returned:
    /// `updated_at > s OR (updated_at = s AND id > last)`. Values are double-quoted because timestamps
    /// contain `.` and `:`, which are reserved inside logic trees.
    static func afterFilter(_ cursor: SharedListPageCursor) -> String {
        let stamp = quoted(cursor.updatedAt ?? "")
        return "updated_at.gt.\(stamp),and(updated_at.eq.\(stamp),id.gt.\(quoted(cursor.id)))"
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
