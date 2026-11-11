import Foundation

/// Mirrors the JSON returned by POST /transcribe. Unknown keys are ignored by Codable.
struct TranscribeResponseDto: Decodable, Equatable, Sendable {
    let transcript: String?
    let items: [TranscribeItemDto]

    init(transcript: String? = nil, items: [TranscribeItemDto] = []) {
        self.transcript = transcript
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript)
        items = try c.decodeIfPresent([TranscribeItemDto].self, forKey: .items) ?? []
    }

    private enum CodingKeys: String, CodingKey { case transcript, items }
}

/// One parsed item. Quantity is a number and unit is separate; `location` is the store.
struct TranscribeItemDto: Decodable, Equatable, Sendable {
    let name: String
    let quantity: Int?
    let unit: String?
    let category: String?
    let location: String?
    let note: String?

    init(
        name: String,
        quantity: Int? = nil,
        unit: String? = nil,
        category: String? = nil,
        location: String? = nil,
        note: String? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.location = location
        self.note = note
    }

    /// Flattens quantity + unit: 2 + "bottles" -> "2 bottles", 2 + nil -> "2", nil + nil -> nil.
    func toItemDraft() -> ItemDraft {
        let parts = [quantity.map(String.init), unit].compactMap { $0 }
        let joined = parts.joined(separator: " ")
        let isBlank = joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ItemDraft(
            name: name,
            quantity: isBlank ? nil : joined,
            note: note,
            category: category,
            shop: location
        )
    }
}

/// One parsed item the user spoke. Only `name` is guaranteed.
struct ItemDraft: Equatable, Sendable {
    var name: String
    var quantity: String?
    var note: String?
    var category: String?
    /// Backend "location": the store this item belongs to.
    var shop: String?

    init(name: String, quantity: String? = nil, note: String? = nil, category: String? = nil, shop: String? = nil) {
        self.name = name
        self.quantity = quantity
        self.note = note
        self.category = category
        self.shop = shop
    }
}
