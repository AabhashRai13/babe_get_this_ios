import Foundation

/// One item on a list. In-memory until the GRDB layer lands.
struct ShoppingItem: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var quantity: String
    var category: String?
    var shop: String?
    var note: String?
    var isPickedUp: Bool

    init(id: String = UUID().uuidString, name: String, quantity: String, category: String? = nil,
         shop: String? = nil, note: String? = nil, isPickedUp: Bool = false) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.category = category
        self.shop = shop
        self.note = note
        self.isPickedUp = isPickedUp
    }

    /// Fixed items for the "Sunday Roast" sample list (screenshots and previews).
    static let sundayRoast: [ShoppingItem] = [
        .init(id: "sr-red-wine", name: "Red wine", quantity: "1 bottle", category: "Beer, Wine & Spirits",
              shop: "Dan Murphys", note: "Something that goes with lamb"),
        .init(id: "sr-lamb-leg", name: "Lamb leg", quantity: "2.5 kg", category: "Meat & Seafood",
              shop: "The Butcher Block", note: "Bone in - ask for the shank end"),
        .init(id: "sr-double-cream", name: "Double cream", quantity: "300 ml", category: "Dairy & Eggs",
              shop: "Woolworths", note: "For the gratin"),
        .init(id: "sr-baby-potatoes", name: "Baby potatoes", quantity: "1.5 kg", category: "Fruits & Vegetables",
              shop: "Woolworths", note: "The waxy ones, not floury"),
        .init(id: "sr-sourdough", name: "Sourdough", quantity: "1 loaf", category: "Bakery & Bread",
              shop: "Woolworths", note: "Get there before 10 or it is gone", isPickedUp: true),
    ]
}

/// Active items under one category heading.
struct CategoryGroup: Identifiable, Equatable {
    let name: String?
    let items: [ShoppingItem]
    var id: String { name ?? "" }
}

/// Active items under one shop heading, split by category.
struct ShopGroup: Identifiable, Equatable {
    let shop: String?
    let categories: [CategoryGroup]
    var id: String { shop ?? "" }
}

/// Fields of the add-item sheet, with the Android length limits and required-field rules.
struct ItemDraft: Equatable {
    static let nameLimit = 60
    static let noteLimit = 80
    static let shopLimit = 40

    var name = ""
    var quantity = ""
    var category: String?
    var shop = ""
    var note = ""

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
