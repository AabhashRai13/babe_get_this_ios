import Foundation

/// One row on the lists overview. In-memory until the GRDB layer lands.
struct ShoppingListSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var name: String
    var totalItems: Int
    var pickedUpItems: Int
    var updatedAt: Date

    /// Android: a list is completed when it has items and every one is picked up.
    var isCompleted: Bool { totalItems > 0 && pickedUpItems >= totalItems }
    var itemsToGet: Int { max(totalItems - pickedUpItems, 0) }

    static let samples: [ShoppingListSummary] = [
        .init(id: "sample-sunday-roast", name: "Sunday Roast", totalItems: 7, pickedUpItems: 3, updatedAt: .now),
        .init(id: "sample-byron-bay", name: "Byron Bay Weekend", totalItems: 5, pickedUpItems: 0, updatedAt: .now),
        .init(id: "sample-anniversary", name: "Anniversary Dinner", totalItems: 5, pickedUpItems: 0, updatedAt: .now),
        .init(id: "sample-bbq", name: "Saturday BBQ", totalItems: 4, pickedUpItems: 4, updatedAt: .now),
    ]
}
