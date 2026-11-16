import Supabase
import XCTest
@testable import BabeGetThis

/// SRV-06: membership is the security boundary (migration 001's RLS). A signed-in stranger sees nothing
/// and can change nothing; membership only comes from the creator trigger and the join RPC.
final class RowLevelSecurityIntegrationTests: LocalSupabaseTestCase {
    func testNonMemberCanNeitherReadNorWriteAList() async throws {
        let owner = try await makeUser("owner")
        let stranger = try await makeUser("stranger")
        let list = try await create(newList("Private", by: owner, shareCode: newShareCode()), by: owner)
        let milk = newItem("Milk", in: list)
        try await owner.remote.upsertItems([milk])

        // Reads come back empty, not as an error.
        let lists = try await stranger.remote.fetchList(listId: list.id, sinceIso: nil)
        XCTAssertEqual(lists, [])
        let items = try await stranger.remote.fetchItems(listId: list.id, sinceIso: nil)
        XCTAssertEqual(items, [])
        let allLists = try await stranger.remote.fetchAllLists()
        XCTAssertEqual(allLists, [])
        let accountItems = try await stranger.remote.fetchAccountItems(sinceIso: nil)
        XCTAssertEqual(accountItems, [])

        // Writes are refused.
        await assertPostgrestError("42501", "a stranger adds an item") {
            try await stranger.remote.upsertItems([self.newItem("Crisps", in: list)])
        }
        var tampered = milk
        tampered.name = "Gin"
        await assertPostgrestError("42501", "a stranger edits an item") {
            try await stranger.remote.upsertItems([tampered])
        }
        var renamed = list
        renamed.name = "Mine now"
        renamed.createdBy = stranger.id
        await assertPostgrestError("42501", "a stranger renames the list") {
            try await stranger.remote.upsertLists([renamed])
        }
        await assertPostgrestError("42501", "a stranger makes a list in someone else's name") {
            _ = try await stranger.remote.insertList(self.newList("Forged", by: owner))
        }

        // Nothing changed for the owner.
        let ownerLists = try await owner.remote.fetchList(listId: list.id, sinceIso: nil)
        XCTAssertEqual(ownerLists.first?.name, "Private")
        XCTAssertEqual(ownerLists.first?.createdBy, owner.id)
        let ownerItems = try await owner.remote.fetchItems(listId: list.id, sinceIso: nil)
        XCTAssertEqual(ownerItems.map(\.name), ["Milk"])
    }

    func testMembershipOnlyComesFromTheJoinRPCAndNeedsASession() async throws {
        let owner = try await makeUser("owner")
        let stranger = try await makeUser("stranger")
        let list = try await create(newList("Members only", by: owner, shareCode: newShareCode()), by: owner)

        // No INSERT policy on list_members: a member row can't be written directly.
        struct Membership: Encodable { let list_id: String; let user_id: String }
        await assertPostgrestError("42501", "a stranger inserts their own membership") {
            try await stranger.client.from("list_members")
                .insert(Membership(list_id: list.id, user_id: stranger.id), returning: .minimal)
                .execute()
        }

        // Signed out (anon key only), the join RPC is not even callable.
        let signedOut = SupabaseSharedListRemote(client: LocalSupabase.makeClient(endpoint))
        await assertPostgrestError("42501", "the join RPC without a session") {
            _ = try await signedOut.joinListByCode(try XCTUnwrap(list.shareCode))
        }

        let strangerLists = try await stranger.remote.fetchAllLists()
        XCTAssertEqual(strangerLists, [], "neither attempt made the stranger a member")
    }
}
