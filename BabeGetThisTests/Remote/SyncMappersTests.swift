import XCTest
@testable import BabeGetThis

/// Port of Android `SyncMappersTest` (origin/feat/got-this). The two `picked_up_at` round-trip cases are
/// replaced by `testEncodedItemRowNeverContainsPickedUpAt` and `testDecodingIgnoresPickedUpAt`:
/// iOS v1 acts as a pre-Got-This client and must never send `picked_up_at`.
final class SyncMappersTests: XCTestCase {
    private let iso = "2026-08-01T10:00:00Z"
    private let ms: Int64 = 1_785_578_400_000 // == iso

    private func listRecord(shareCode: String? = "ABC123", deletedAt: Int64? = nil) -> LocalListRecord {
        LocalListRecord(
            id: "list-1",
            name: "Groceries",
            createdAt: 1,
            updatedAt: 2,
            isLocked: true,
            shareCode: shareCode,
            deletedAt: deletedAt,
            pendingSync: true
        )
    }

    private func itemRecord(deletedAt: Int64? = nil) -> LocalItemRecord {
        LocalItemRecord(
            id: "item-1", listId: "list-1", name: "Milk", quantity: "2 bags",
            isPickedUp: true, categoryId: "cat-1", shop: "Costco", note: "the blue one",
            createdAt: 1, updatedAt: 2, deletedAt: deletedAt, pendingSync: true
        )
    }

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - iso helpers

    func testIsoRoundTripsThroughMillis() throws {
        XCTAssertEqual(try iso.isoToMillis(), ms)
        XCTAssertEqual(try ms.millisToIso().isoToMillis(), ms)
    }

    func testIsoWithExplicitOffsetParses() throws {
        XCTAssertEqual(try "2026-08-01T10:00:00+00:00".isoToMillis(), ms)
    }

    // MARK: - record → row (push direction)

    func testListToRowCarriesCodeAndCreatorAndLeavesTheClockToTheServer() {
        let row = listRecord().toRow(createdBy: "user-9")

        XCTAssertEqual(row.id, "list-1")
        XCTAssertEqual(row.shareCode, "ABC123")
        XCTAssertEqual(row.createdBy, "user-9")
        XCTAssertNil(row.updatedAt, "server owns updated_at")
        XCTAssertNil(row.deletedAt)
    }

    func testAnUnsharedListMapsToARowWithANullShareCode() {
        // Every account list syncs; only shared ones carry a code (docs/technical-decisions/008).
        let row = listRecord(shareCode: nil).toRow(createdBy: "user-9")

        XCTAssertNil(row.shareCode)
        XCTAssertEqual(row.createdBy, "user-9")
    }

    func testTombstonesTravelAsIsoDeletedAt() {
        XCTAssertEqual(listRecord(deletedAt: ms).toRow(createdBy: "u").deletedAt, iso)
        XCTAssertEqual(itemRecord(deletedAt: ms).toRow().deletedAt, iso)
    }

    func testItemToRowCopiesEverySyncedField() {
        XCTAssertEqual(
            itemRecord().toRow(),
            ItemRow(
                id: "item-1", listId: "list-1", name: "Milk", quantity: "2 bags",
                isPickedUp: true, categoryId: "cat-1", shop: "Costco",
                note: "the blue one", updatedAt: nil, deletedAt: nil
            )
        )
    }

    // MARK: - picked_up_at (replaces the two Android round-trip cases)

    func testEncodedItemRowNeverContainsPickedUpAt() throws {
        let object = try json(itemRecord().toRow())

        XCTAssertFalse(object.keys.contains("picked_up_at"), "iOS v1 must not send picked_up_at, not even as null")
        XCTAssertEqual(object["is_picked_up"] as? Bool, true)
    }

    func testDecodingIgnoresPickedUpAt() throws {
        let data = Data("""
        {"id":"i","list_id":"l","name":"n","quantity":"1","is_picked_up":true,
         "updated_at":"\(iso)","deleted_at":null,"picked_up_at":"\(iso)"}
        """.utf8)

        let row = try JSONDecoder().decode(ItemRow.self, from: data)
        XCTAssertEqual(row, ItemRow(id: "i", listId: "l", name: "n", quantity: "1", isPickedUp: true, updatedAt: iso))
        XCTAssertFalse(try json(row).keys.contains("picked_up_at"))
    }

    // MARK: - row → record (apply direction)

    func testNewListRowLandsCleanWithTheServerClock() throws {
        let record = try ListRow(id: "list-1", name: "Groceries", shareCode: "ABC123", updatedAt: iso)
            .toRecord(local: nil, accountId: "user-1", lockedIds: [])

        XCTAssertEqual(record.updatedAt, ms)
        XCTAssertEqual(record.createdAt, ms, "no local row → server time becomes createdAt")
        XCTAssertFalse(record.isLocked)
        XCTAssertFalse(record.pendingSync)
        XCTAssertEqual(record.shareCode, "ABC123")
    }

    // The lists screen sorts and groups by creation date. A list coming back after sign-out, or onto a
    // second phone, must keep its own date — not become "created" whenever it was last edited.
    func testAPushedRowCarriesTheListsCreationTime() {
        let row = LocalListRecord(id: "l", name: "n", createdAt: 1_000, updatedAt: 2_000)
            .toRow(createdBy: "user-9")

        XCTAssertEqual(row.createdAt, "1970-01-01T00:00:01Z")
    }

    func testARediscoveredListKeepsItsCreationDate() throws {
        let record = try ListRow(id: "l", name: "n", createdAt: "2026-01-01T00:00:00Z", updatedAt: iso)
            .toRecord(local: nil, accountId: "user-1", lockedIds: [])

        XCTAssertEqual(record.createdAt, 1_767_225_600_000)
    }

    // created_at is write-once on the server and set by whichever new-version phone pushed first. A row
    // already on this phone keeps its own date rather than jumping to that one.
    func testAListAlreadyHereKeepsItsOwnCreationDateOverTheServers() throws {
        let record = try ListRow(id: "list-1", name: "n", createdAt: "2026-01-01T00:00:00Z", updatedAt: iso)
            .toRecord(local: listRecord(), accountId: "user-1", lockedIds: [])

        XCTAssertEqual(record.createdAt, 1)
    }

    // Whatever the server sends is the signed-in account's list, and it is on the server by definition
    // (docs/technical-decisions/008).
    func testAServerRowBecomesAnOwnedOnServerRecord() throws {
        let record = try ListRow(id: "list-1", name: "Groceries", updatedAt: iso)
            .toRecord(local: nil, accountId: "user-1", lockedIds: [])

        XCTAssertEqual(record.accountId, "user-1")
        XCTAssertTrue(record.onServer)
        XCTAssertNil(record.shareCode)
    }

    func testAReturningListIsReLockedIfThisDeviceHadLockedIt() throws {
        let row = ListRow(id: "list-1", name: "Groceries", updatedAt: iso)

        XCTAssertTrue(try row.toRecord(local: nil, accountId: "user-1", lockedIds: ["list-1"]).isLocked)
        XCTAssertFalse(try row.toRecord(local: nil, accountId: "user-1", lockedIds: ["other"]).isLocked)
    }

    func testExistingLocalListKeepsDeviceLocalConcerns() throws {
        let record = try ListRow(id: "list-1", name: "Renamed", shareCode: "ABC123", updatedAt: iso)
            .toRecord(local: listRecord(), accountId: "user-1", lockedIds: [])

        XCTAssertEqual(record.name, "Renamed")
        XCTAssertEqual(record.createdAt, 1, "createdAt preserved")
        XCTAssertTrue(record.isLocked, "PIN lock preserved")
        XCTAssertFalse(record.pendingSync, "applied rows are clean")
    }

    func testIncomingTombstoneBecomesALocalTombstone() throws {
        let record = try ItemRow(id: "item-1", listId: "list-1", name: "Milk", quantity: "1", updatedAt: iso, deletedAt: iso)
            .toRecord(local: itemRecord())

        XCTAssertEqual(record.deletedAt, ms)
    }

    func testRowWithoutServerClockIsRejected() {
        XCTAssertThrowsError(try ItemRow(id: "i", listId: "l", name: "n", quantity: "1", updatedAt: nil).toRecord(local: nil)) {
            XCTAssertEqual($0 as? SyncMappingError, .missingServerClock)
        }
        XCTAssertThrowsError(
            try ListRow(id: "l", name: "n", shareCode: "c", updatedAt: nil)
                .toRecord(local: nil, accountId: "user-1", lockedIds: [])
        ) {
            XCTAssertEqual($0 as? SyncMappingError, .missingServerClock)
        }
    }
}
