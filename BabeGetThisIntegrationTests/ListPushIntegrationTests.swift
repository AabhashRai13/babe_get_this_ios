import Supabase
import XCTest
@testable import BabeGetThis

/// SRV-06: how SyncEngine pushes lists and items, against the real migrations (001, 003).
final class ListPushIntegrationTests: LocalSupabaseTestCase {
    /// A list's first push is a plain INSERT; every later push of it is an upsert.
    func testFirstPushIsAPlainInsertAndLaterPushesUpsert() async throws {
        let owner = try await makeUser("owner")
        let list = newList("Groceries", by: owner)

        let inserted = try await owner.remote.insertList(list)
        XCTAssertTrue(inserted)
        let firstRows = try await owner.remote.fetchList(listId: list.id, sinceIso: nil)
        let first = try XCTUnwrap(firstRows.first)
        XCTAssertEqual(first.name, "Groceries")
        XCTAssertEqual(first.createdBy, owner.id)
        XCTAssertNil(first.shareCode, "an unshared account list has no code (migration 003)")
        XCTAssertEqual(try XCTUnwrap(first.createdAt).isoToMillis(), try XCTUnwrap(list.createdAt).isoToMillis())
        let firstClock = try XCTUnwrap(first.updatedAt, "the server stamps updated_at").isoToMillis()

        // A repeated first push (it reached the server but was never marked synced) reports "already there".
        let insertedAgain = try await owner.remote.insertList(list)
        XCTAssertFalse(insertedAgain)

        var renamed = list
        renamed.name = "Weekly shop"
        try await owner.remote.upsertLists([renamed])
        let secondRows = try await owner.remote.fetchList(listId: list.id, sinceIso: nil)
        let second = try XCTUnwrap(secondRows.first)
        XCTAssertEqual(second.name, "Weekly shop")
        XCTAssertEqual(second.createdBy, owner.id)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(second.updatedAt).isoToMillis(), firstClock)

        // Items push after their list: a new item and a later edit of it are both upserts.
        var item = newItem("Milk", in: list)
        try await owner.remote.upsertItems([item])
        item.quantity = "2 bottles"
        item.isPickedUp = true
        try await owner.remote.upsertItems([item])
        let items = try await owner.remote.fetchItems(listId: list.id, sinceIso: nil)
        XCTAssertEqual(items.map(\.id), [item.id])
        XCTAssertEqual(items.first?.quantity, "2 bottles")
        XCTAssertEqual(items.first?.isPickedUp, true)
    }

    /// Why the first push can't be an upsert: the upsert's row check runs before the creator's
    /// membership exists, so RLS refuses it (42501) and nothing is written.
    func testUpsertOfABrandNewListIsRefusedByRLS() async throws {
        let owner = try await makeUser("owner")
        let list = newList("Never inserted", by: owner)

        await assertPostgrestError("42501", "upsert of a list the server has never seen") {
            try await owner.remote.upsertLists([list])
        }

        let rows = try await owner.remote.fetchList(listId: list.id, sinceIso: nil)
        XCTAssertEqual(rows, [])
    }
}
