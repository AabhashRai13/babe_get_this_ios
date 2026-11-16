import CryptoKit
import Supabase
import XCTest
@testable import BabeGetThis

/// SYNC-18: iOS v1 never sends `picked_up_at` (it acts as a pre-Got-This client), so migration 006's
/// `items_track_picked_up_at` trigger records each iOS tick as a 'legacy' tick: it stamps the item with
/// the server time and writes the tick, which credits a purchase to everyone on the list. No client code.
///
/// `ticks` has no client policy, so its `source` column can't be read with a user's key. These tests prove
/// the source instead: they never call `record_ticks` (the only 'app' writer) and there is no backfill, so
/// the only path that can write a tick for the item is the trigger's legacy branch, whose tick id is
/// md5("<item id>:<epoch ms of the stamped picked_up_at>"), exactly as the purchases show.
final class LegacyTickIntegrationTests: LocalSupabaseTestCase {
    private struct ItemTickState: Decodable {
        let id: String
        let is_picked_up: Bool
        let picked_up_at: String?
    }

    private struct IdOnly: Decodable {
        let id: String
    }

    private struct Purchase: Decodable {
        let user_id: String
        let tick_id: String
        let source_item_id: String
        let name: String
        let bought_at: String
        let deleted_at: String?
    }

    func testTickPushedWithoutPickedUpAtIsRecordedAsALegacyTick() async throws {
        let owner = try await makeUser("owner")
        let partner = try await makeUser("partner")
        let list = try await sharedList("Got this", owner: owner, partner: partner)
        var milk = newItem("Milk", in: list)
        try await owner.remote.upsertItems([milk])
        let unticked = try await tickState(of: milk, as: owner)
        XCTAssertNil(unticked.picked_up_at)
        let noPurchases = try await purchases(of: milk, as: owner)
        XCTAssertEqual(noPurchases.count, 0)

        // The iOS tick: the app's own row, which has no picked_up_at key at all.
        milk.isPickedUp = true
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(milk)) as? [String: Any]
        XCTAssertNotNil(body?["is_picked_up"])
        XCTAssertNil(body?["picked_up_at"], "iOS v1 must not send picked_up_at")
        try await owner.remote.upsertItems([milk])

        let ticked = try await tickState(of: milk, as: owner)
        XCTAssertTrue(ticked.is_picked_up)
        let stamped = try XCTUnwrap(ticked.picked_up_at, "the trigger stamps the server's tick time")
        let tickId = Self.legacyTickId(itemId: milk.id, millis: try stamped.isoToMillis())

        // One purchase each for the owner and the partner (a member before the tick), from that tick.
        let ownerPurchases = try await purchases(of: milk, as: owner)
        let partnerPurchases = try await purchases(of: milk, as: partner)
        for (who, rows, userId) in [("owner", ownerPurchases, owner.id), ("partner", partnerPurchases, partner.id)] {
            XCTAssertEqual(rows.count, 1, "\(who)'s purchases")
            let purchase = try XCTUnwrap(rows.first)
            XCTAssertEqual(purchase.user_id, userId)
            XCTAssertEqual(purchase.tick_id, tickId, "\(who): the legacy tick's id")
            XCTAssertEqual(purchase.name, "Milk")
            XCTAssertEqual(try purchase.bought_at.isoToMillis(), try stamped.isoToMillis())
            XCTAssertNil(purchase.deleted_at)
        }

        // The tick rows themselves stay server-side.
        let visibleTicks: [IdOnly] = try await owner.client.from("ticks").select("id").execute().value
        XCTAssertEqual(visibleTicks.count, 0, "ticks have no client policy")

        // The next push of the same, still ticked row is not another tick.
        milk.note = "semi-skimmed"
        try await owner.remote.upsertItems([milk])
        let after = try await tickState(of: milk, as: owner)
        let restamped = try XCTUnwrap(after.picked_up_at)
        XCTAssertEqual(try restamped.isoToMillis(), try stamped.isoToMillis(), "the tick time only moves on a new tick")
        let ownerAfter = try await purchases(of: milk, as: owner)
        XCTAssertEqual(ownerAfter.map(\.tick_id), [tickId])
    }

    /// The first push of an item that is already ticked takes the trigger's INSERT branch.
    func testFirstPushOfATickedItemIsRecordedAsALegacyTick() async throws {
        let owner = try await makeUser("owner")
        let list = try await create(newList("Solo", by: owner), by: owner)
        let bread = newItem("Bread", in: list, isPickedUp: true)

        try await owner.remote.upsertItems([bread])

        let state = try await tickState(of: bread, as: owner)
        let stamped = try XCTUnwrap(state.picked_up_at)
        let rows = try await purchases(of: bread, as: owner)
        XCTAssertEqual(rows.map(\.tick_id), [Self.legacyTickId(itemId: bread.id, millis: try stamped.isoToMillis())])
        XCTAssertEqual(rows.first?.user_id, owner.id)
    }

    // MARK: - Helpers

    private func tickState(of item: ItemRow, as user: TestUser) async throws -> ItemTickState {
        let rows: [ItemTickState] = try await user.client.from("items")
            .select("id, is_picked_up, picked_up_at")
            .eq("id", value: item.id)
            .execute()
            .value
        return try XCTUnwrap(rows.first)
    }

    private func purchases(of item: ItemRow, as user: TestUser) async throws -> [Purchase] {
        try await user.client.from("purchases")
            .select("user_id, tick_id, source_item_id, name, bought_at, deleted_at")
            .eq("source_item_id", value: item.id)
            .execute()
            .value
    }

    /// got_this_private.tick_id: md5("<item id>:<epoch millis>") read as a uuid.
    static func legacyTickId(itemId: String, millis: Int64) -> String {
        let hex = Insecure.MD5.hash(data: Data("\(itemId):\(millis)".utf8)).map { String(format: "%02x", $0) }.joined()
        let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                     hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
        return parts.joined(separator: "-")
    }
}
