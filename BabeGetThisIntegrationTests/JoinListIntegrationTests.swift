import Supabase
import XCTest
@testable import BabeGetThis

/// SRV-06: the `join_list_by_code` RPC (migration 001) through SupabaseSharedListRemote.
final class JoinListIntegrationTests: LocalSupabaseTestCase {
    func testJoinByCodeMakesThePartnerAFullMember() async throws {
        let owner = try await makeUser("owner")
        let partner = try await makeUser("partner")
        let list = try await create(newList("Shared", by: owner), by: owner)
        let milk = newItem("Milk", in: list)
        try await owner.remote.upsertItems([milk])

        // Sharing a list that already syncs: a targeted UPDATE that sets the code once.
        let code = newShareCode()
        let stored = try await owner.remote.setShareCode(listId: list.id, code: code)
        XCTAssertEqual(stored, code)
        let kept = try await owner.remote.setShareCode(listId: list.id, code: newShareCode())
        XCTAssertEqual(kept, code, "the first code is write-once (migration 003)")

        // The RPC trims and uppercases what was typed.
        let joined = try await partner.remote.joinListByCode("  \(code.lowercased()) ")
        XCTAssertEqual(joined, list.id)
        let joinedAgain = try await partner.remote.joinListByCode(code)
        XCTAssertEqual(joinedAgain, list.id, "joining twice is idempotent")

        // Membership gives the partner the list, its items, and the right to edit them.
        let discovered = try await partner.remote.fetchAllLists()
        XCTAssertEqual(discovered.map(\.id), [list.id])
        XCTAssertEqual(discovered.first?.createdBy, owner.id)
        let partnerItems = try await partner.remote.fetchItems(listId: list.id, sinceIso: nil)
        XCTAssertEqual(partnerItems.map(\.id), [milk.id])

        let bread = newItem("Bread", in: list)
        try await partner.remote.upsertItems([bread])
        let ownerItems = try await owner.remote.fetchItems(listId: list.id, sinceIso: nil)
        XCTAssertEqual(Set(ownerItems.map(\.id)), [milk.id, bread.id])
    }

    func testJoinWithAnUnknownCodeReturnsNil() async throws {
        let partner = try await makeUser("partner")

        // 0 is outside the code alphabet, so no generated code can match.
        let joined = try await partner.remote.joinListByCode("ZZZZ00")

        XCTAssertNil(joined, "the RPC's invalid_code is a user-facing outcome, not an error")
        let lists = try await partner.remote.fetchAllLists()
        XCTAssertEqual(lists, [])
    }
}
