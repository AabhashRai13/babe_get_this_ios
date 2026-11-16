import Supabase
import XCTest
@testable import BabeGetThis

/// SRV-06: realtime only says "worth asking"; the catch-up read then brings the data (migration 001's
/// publication, filtered per subscriber by RLS).
final class RealtimeCatchUpIntegrationTests: LocalSupabaseTestCase {
    func testPartnersEditRaisesAnEventAndCatchUpBringsItIn() async throws {
        let owner = try await makeUser("owner")
        let partner = try await makeUser("partner")
        let list = try await sharedList("Realtime", owner: owner, partner: partner)
        let before = try await owner.remote.fetchList(listId: list.id, sinceIso: nil)
        let sincePoint = try XCTUnwrap(before.first?.updatedAt)

        // The owner has the list open: one channel, every element = "catch up now".
        let events = EventCounter()
        let listener = Task {
            do {
                for try await _ in owner.remote.changes(listId: list.id) { await events.increment() }
            } catch {
                await events.fail(error)
            }
        }
        defer { listener.cancel() }

        // The first element is the channel's join.
        let subscribed = try await eventually(within: 20) {
            let count = await events.count
            let failed = await events.failure != nil
            return count >= 1 || failed
        }
        let failure = await events.failure
        XCTAssertNil(failure, "the channel failed: \(String(describing: failure))")
        XCTAssertTrue(subscribed, "the channel never reported a join")
        let joinEvents = await events.count
        let quiet = try await owner.remote.fetchItems(listId: list.id, sinceIso: sincePoint)
        XCTAssertEqual(quiet, [], "nothing to catch up yet")

        // The partner adds an item. Postgres changes can lag the join reply by a moment, so the write is
        // repeated (an edit of the same item) until an event arrives.
        var eggs = newItem("Eggs", in: list)
        var heard = false
        for attempt in 1...4 where !heard {
            eggs.quantity = "\(attempt * 6)"
            try await partner.remote.upsertItems([eggs])
            heard = try await eventually(within: 5) { await events.count > joinEvents }
        }
        XCTAssertTrue(heard, "no realtime event for the partner's item")

        // The catch-up the event asks for.
        let caughtUp = try await owner.remote.fetchItems(listId: list.id, sinceIso: sincePoint)
        XCTAssertEqual(caughtUp.map(\.id), [eggs.id])
        XCTAssertEqual(caughtUp.first?.name, "Eggs")
        XCTAssertEqual(caughtUp.first?.quantity, eggs.quantity)
    }
}
