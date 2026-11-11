import XCTest
@testable import BabeGetThis

/// Wire shape of the `lists` / `items` rows (supabase/migrations/001–006) and the timestamp helpers.
final class SyncRowsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testListRowOptionalsDecodeAsNilWhenAbsent() throws {
        let row = try decode(ListRow.self, #"{"id":"l","name":"n"}"#)

        XCTAssertEqual(row, ListRow(id: "l", name: "n"))
        XCTAssertNil(row.shareCode)
        XCTAssertNil(row.createdBy)
        XCTAssertNil(row.createdAt)
        XCTAssertNil(row.updatedAt)
        XCTAssertNil(row.deletedAt)
    }

    func testListRowOptionalsDecodeAsNilWhenNull() throws {
        let row = try decode(ListRow.self, """
        {"id":"l","name":"n","share_code":null,"created_by":null,
         "created_at":null,"updated_at":null,"deleted_at":null}
        """)

        XCTAssertEqual(row, ListRow(id: "l", name: "n"))
    }

    func testListRowDecodesAServerRow() throws {
        let row = try decode(ListRow.self, """
        {"id":"l","name":"n","share_code":"ABC123","created_by":"u",
         "created_at":"2026-01-01T00:00:00+00:00","updated_at":"2026-08-01T10:00:00.123456+00:00",
         "deleted_at":null}
        """)

        XCTAssertEqual(row.shareCode, "ABC123")
        XCTAssertEqual(row.createdBy, "u")
        XCTAssertEqual(row.createdAt, "2026-01-01T00:00:00+00:00")
        XCTAssertEqual(try row.updatedAt?.isoToMillis(), 1_785_578_400_123)
    }

    func testItemRowOptionalsDecodeAsNilAndPickedUpDefaultsToFalse() throws {
        let row = try decode(ItemRow.self, #"{"id":"i","list_id":"l","name":"n","quantity":"1","shop":null}"#)

        XCTAssertEqual(row, ItemRow(id: "i", listId: "l", name: "n", quantity: "1"))
        XCTAssertFalse(row.isPickedUp)
    }

    /// Android encodes with `encodeDefaults = true, explicitNulls = true`: nulls travel as JSON null.
    func testRowsEncodeSnakeCaseKeysWithExplicitNulls() throws {
        let list = try object(ListRow(id: "l", name: "n"))
        XCTAssertEqual(Set(list.keys), ["id", "name", "share_code", "created_by", "created_at", "updated_at", "deleted_at"])
        XCTAssertTrue(list["share_code"] is NSNull)

        let item = try object(ItemRow(id: "i", listId: "l", name: "n", quantity: "1"))
        XCTAssertEqual(
            Set(item.keys),
            ["id", "list_id", "name", "quantity", "is_picked_up", "category_id", "shop", "note", "updated_at", "deleted_at"]
        )
        XCTAssertTrue(item["updated_at"] is NSNull)
    }

    func testMillisToIsoMatchesKotlinInstantToString() {
        XCTAssertEqual(Int64(0).millisToIso(), "1970-01-01T00:00:00Z")
        XCTAssertEqual(Int64(1_785_578_400_123).millisToIso(), "2026-08-01T10:00:00.123Z")
        XCTAssertEqual(Int64(1_785_578_400_100).millisToIso(), "2026-08-01T10:00:00.100Z")
        XCTAssertEqual(Int64(-1).millisToIso(), "1969-12-31T23:59:59.999Z")
        XCTAssertEqual(Int64(951_782_400_000).millisToIso(), "2000-02-29T00:00:00Z")
    }

    func testIsoToMillisHandlesFractionsAndOffsets() throws {
        XCTAssertEqual(try "2026-08-01T10:00:00.123456789Z".isoToMillis(), 1_785_578_400_123)
        XCTAssertEqual(try "2026-08-01T10:00:00.5Z".isoToMillis(), 1_785_578_400_500)
        XCTAssertEqual(try "2026-08-01T12:30:00+02:30".isoToMillis(), 1_785_578_400_000)
        XCTAssertEqual(try "2026-08-01T05:00:00-05:00".isoToMillis(), 1_785_578_400_000)
        XCTAssertEqual(try "1969-12-31T23:59:59.999Z".isoToMillis(), -1)
    }

    func testIsoToMillisRejectsMalformedInput() {
        for bad in ["", "2026-08-01", "2026-08-01T10:00:00", "2026-13-01T10:00:00Z", "2026-02-30T10:00:00Z",
                    "2026-08-01T24:00:00Z", "2026-08-01T10:00:00Zjunk", "2026-08-01T10:00:00.Z"] {
            XCTAssertThrowsError(try bad.isoToMillis(), bad) {
                XCTAssertEqual($0 as? SyncMappingError, .invalidTimestamp(bad))
            }
        }
    }
}
