import Foundation

/// One item on the list detail screen, mapped from the repository's `StoredShoppingItem`.
struct ShoppingItem: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var quantity: String
    /// A `categories` row id (Android `ShoppingItem.categoryId`), e.g. "cat-dairy-eggs".
    var categoryId: String?
    /// The category's display name (nil when unset or unknown).
    var categoryName: String?
    var shop: String?
    var note: String?
    var isPickedUp: Bool

    /// Without a `categoryName` the name is resolved from the default categories.
    init(id: String = UUID().uuidString, name: String, quantity: String, categoryId: String? = nil,
         categoryName: String? = nil, shop: String? = nil, note: String? = nil, isPickedUp: Bool = false) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.categoryId = categoryId
        self.categoryName = categoryName ?? DefaultCategories.name(for: categoryId)
        self.shop = shop
        self.note = note
        self.isPickedUp = isPickedUp
    }

    /// The repository resolves the name from the `categories` table, so custom categories show too.
    init(_ stored: StoredShoppingItem) {
        self.init(id: stored.id, name: stored.name, quantity: stored.quantity, categoryId: stored.categoryId,
                  categoryName: stored.categoryName, shop: stored.shop, note: stored.note,
                  isPickedUp: stored.isPickedUp)
    }

    /// The sample list `sundayRoast` is seeded into (`ShoppingListSummary.samples`).
    static let sundayRoastListId = "sample-sunday-roast"

    /// Fixed items for the "Sunday Roast" sample list (screenshots and previews).
    static let sundayRoast: [ShoppingItem] = [
        .init(id: "sr-red-wine", name: "Red wine", quantity: "1 bottle", categoryId: "cat-alcohol",
              shop: "Dan Murphys", note: "Something that goes with lamb"),
        .init(id: "sr-lamb-leg", name: "Lamb leg", quantity: "2.5 kg", categoryId: "cat-meat-seafood",
              shop: "The Butcher Block", note: "Bone in - ask for the shank end"),
        .init(id: "sr-double-cream", name: "Double cream", quantity: "300 ml", categoryId: "cat-dairy-eggs",
              shop: "Woolworths", note: "For the gratin"),
        .init(id: "sr-baby-potatoes", name: "Baby potatoes", quantity: "1.5 kg", categoryId: "cat-fruits-vegetables",
              shop: "Woolworths", note: "The waxy ones, not floury"),
        .init(id: "sr-sourdough", name: "Sourdough", quantity: "1 loaf", categoryId: "cat-bakery-bread",
              shop: "Woolworths", note: "Get there before 10 or it is gone", isPickedUp: true),
    ]
}

/// Active items under one category heading (Android `CategorySection`).
struct CategoryGroup: Identifiable, Equatable {
    /// The category's name; nil is the uncategorized bucket.
    let name: String?
    let items: [ShoppingItem]
    var id: String { name ?? "" }
    var title: String { name ?? "Uncategorized" }
}

/// Active items under one shop heading, split by category (Android `ShopSection`).
struct ShopGroup: Identifiable, Equatable {
    /// nil is the no-shop group.
    let shop: String?
    let categories: [CategoryGroup]
    var id: String { shop ?? "" }
    var title: String { shop ?? "General" }

    /// A shop whose only bucket is uncategorized shows no category header, so a list
    /// nobody has categorised stays a flat by-shop list.
    var hidesCategoryHeaders: Bool { categories.count == 1 && categories[0].name == nil }
}

/// Fields of the add-item sheet, with the Android length limits and required-field rules.
struct ItemDraft: Equatable {
    static let nameLimit = 60
    static let noteLimit = 80
    static let shopLimit = 40

    var name = ""
    var quantity = ""
    var categoryId: String?
    var shop = ""
    var note = ""

    /// The manual add-item sheet's rule: name and quantity are both required.
    /// Not for spoken items, which often have no quantity: see `isSavableVoiceItem`.
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The voice rule. Android's voice ItemDraft has a nullable quantity and goes straight to
    /// the repository (`draftsToItems`: `quantity.orEmpty()`), so a spoken item needs only a name.
    var isSavableVoiceItem: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
