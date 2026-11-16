import Supabase
import XCTest
@testable import BabeGetThis

/// SRV-04: `delete_user()` (migration 004) removes the caller's solo lists (items cascade) and then the
/// auth user. Lists someone else joined stay with them, `created_by` set to null (migration 002).
final class DeleteUserIntegrationTests: LocalSupabaseTestCase {
    func testDeleteUserRemovesSoloListsAndLeavesSharedListsWithoutACreator() async throws {
        let owner = try await makeUser("owner")
        let partner = try await makeUser("partner")

        // Solo: only the owner is a member. It has a code, but nobody used it, so it is still solo.
        let solo = try await create(newList("Solo", by: owner, shareCode: newShareCode()), by: owner)
        try await owner.remote.upsertItems([newItem("Toothpaste", in: solo)])
        // Shared: the partner joined it.
        let shared = try await sharedList("Household", owner: owner, partner: partner)
        let soap = newItem("Soap", in: shared)
        try await owner.remote.upsertItems([soap])

        // The app's own call (Settings > Delete account).
        try await owner.auth.deleteUser()

        // The shared list stays for the partner, with its items, and no creator.
        let sharedRows = try await partner.remote.fetchList(listId: shared.id, sinceIso: nil)
        let survivor = try XCTUnwrap(sharedRows.first, "the shared list must survive the creator's deletion")
        XCTAssertNil(survivor.createdBy)
        XCTAssertEqual(survivor.name, "Household")
        XCTAssertEqual(survivor.shareCode, shared.shareCode)
        let sharedItems = try await partner.remote.fetchItems(listId: shared.id, sinceIso: nil)
        XCTAssertEqual(sharedItems.map(\.id), [soap.id])
        let partnerLists = try await partner.remote.fetchAllLists()
        XCTAssertEqual(partnerLists.map(\.id), [shared.id])

        // The solo list is gone: its code no longer finds a list (the RPC looks codes up across all lists),
        // so it can't be joined, read or revived. Its items went with it (ON DELETE CASCADE).
        let rejoined = try await partner.remote.joinListByCode(try XCTUnwrap(solo.shareCode))
        XCTAssertNil(rejoined, "the solo list should have been deleted")

        // And the account itself is gone.
        let fresh = SupabaseAuthRemote(client: LocalSupabase.makeClient(endpoint))
        do {
            _ = try await fresh.signIn(email: owner.email, password: owner.password)
            XCTFail("the deleted account could still sign in")
        } catch let error as AuthError {
            XCTAssertEqual(error.errorCode, .invalidCredentials, "\(error)")
        } catch {
            XCTFail("sign-in failed for another reason: \(error)")
        }
    }
}
