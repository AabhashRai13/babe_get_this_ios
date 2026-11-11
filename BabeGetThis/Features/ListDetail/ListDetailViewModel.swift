import Foundation
import Observation

/// In-memory state of the list detail screen (Android `ShoppingItemsViewModel`).
@MainActor
@Observable
final class ListDetailViewModel {
    static let sampleListId = "sample-sunday-roast"
    static let categories = [
        "Fruits & Vegetables", "Dairy & Eggs", "Meat & Seafood", "Bakery & Bread", "Pantry",
        "Frozen", "Snacks", "Drinks", "Beer, Wine & Spirits", "Household", "Other",
    ]

    private(set) var items: [ShoppingItem]
    /// The most recent delete, offered back through the Undo snackbar.
    private(set) var pendingUndo: (item: ShoppingItem, index: Int)?

    init(listId: String) {
        items = listId == Self.sampleListId ? ShoppingItem.sundayRoast : []
    }

    init(items: [ShoppingItem]) {
        self.items = items
    }

    // MARK: Derived state

    var activeItems: [ShoppingItem] { items.filter { !$0.isPickedUp } }
    var completedItems: [ShoppingItem] { items.filter(\.isPickedUp) }
    var totalCount: Int { items.count }
    var pickedUpCount: Int { completedItems.count }
    var progress: Double { totalCount == 0 ? 0 : Double(pickedUpCount) / Double(totalCount) }
    var percent: Int { Int(progress * 100) }
    var isAllDone: Bool { totalCount > 0 && pickedUpCount == totalCount }

    /// Active items grouped by shop, then category. Names sort A–Z; items without a shop or
    /// category come last. Item order inside a category is insertion order.
    var activeGroups: [ShopGroup] {
        let byShop = Dictionary(grouping: activeItems) { $0.shop }
        return Self.sorted(Array(byShop.keys)).map { shop in
            let byCategory = Dictionary(grouping: byShop[shop] ?? []) { $0.category }
            let categories = Self.sorted(Array(byCategory.keys)).map {
                CategoryGroup(name: $0, items: byCategory[$0] ?? [])
            }
            return ShopGroup(shop: shop, categories: categories)
        }
    }

    private static func sorted(_ names: [String?]) -> [String?] {
        names.sorted {
            switch ($0, $1) {
            case let (a?, b?): a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            case (_?, nil): true
            default: false
            }
        }
    }

    // MARK: Actions

    func toggle(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPickedUp.toggle()
    }

    func delete(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        pendingUndo = (items.remove(at: index), index)
    }

    func undoDelete() {
        guard let (item, index) = pendingUndo else { return }
        items.insert(item, at: min(index, items.count))
        pendingUndo = nil
    }

    func dismissUndo() {
        pendingUndo = nil
    }

    /// Adds the item when the draft is valid. Returns whether it was added.
    @discardableResult
    func add(_ draft: ItemDraft) -> Bool {
        guard draft.isValid else { return false }
        let shop = draft.shop.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(ShoppingItem(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: draft.quantity.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category,
            shop: shop.isEmpty ? nil : shop,
            note: note.isEmpty ? nil : note
        ))
        return true
    }
}
