import Foundation

// Wire shapes of the Supabase `lists` / `items` rows (supabase/migrations/001–006), ported from Android
// `core/sync/data/model/SyncRows.kt`. Row ids are the same client-generated UUIDs the local DB uses, so
// there is no id mapping anywhere.
//
// `updatedAt` is nil on push on purpose: the server trigger stamps it, and a client-supplied value would be
// overwritten anyway — phones never own the LWW clock. It is always present on rows read back from the server.
//
// Like Android (`encodeDefaults = true, explicitNulls = true`), nil fields encode as JSON null.
// `picked_up_at` (migration 006) is deliberately absent: iOS v1 acts as a pre-Got-This client, so it never
// sends the key and ignores it on rows it reads.

struct ListRow: Equatable, Sendable {
    var id: String
    var name: String
    /// Nil for an account list that isn't shared (docs/technical-decisions/008).
    var shareCode: String? = nil
    var createdBy: String? = nil
    /// When the list was first made, on whichever phone made it. Write-once on the server (migration 003);
    /// nil on rows from before it existed.
    var createdAt: String? = nil
    var updatedAt: String? = nil
    var deletedAt: String? = nil
}

extension ListRow: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name
        case shareCode = "share_code"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        shareCode = try c.decodeIfPresent(String.self, forKey: .shareCode)
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(shareCode, forKey: .shareCode)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct ItemRow: Equatable, Sendable {
    var id: String
    var listId: String
    var name: String
    var quantity: String
    var isPickedUp: Bool = false
    /// Opaque device-local category id; receiving devices may not resolve it.
    var categoryId: String? = nil
    var shop: String? = nil
    var note: String? = nil
    var updatedAt: String? = nil
    var deletedAt: String? = nil
}

extension ItemRow: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case listId = "list_id"
        case name, quantity
        case isPickedUp = "is_picked_up"
        case categoryId = "category_id"
        case shop, note
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        listId = try c.decode(String.self, forKey: .listId)
        name = try c.decode(String.self, forKey: .name)
        quantity = try c.decode(String.self, forKey: .quantity)
        isPickedUp = try c.decodeIfPresent(Bool.self, forKey: .isPickedUp) ?? false
        categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
        shop = try c.decodeIfPresent(String.self, forKey: .shop)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(listId, forKey: .listId)
        try c.encode(name, forKey: .name)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(isPickedUp, forKey: .isPickedUp)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(shop, forKey: .shop)
        try c.encode(note, forKey: .note)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}
