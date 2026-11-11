import Foundation
import Observation

/// In-memory state of the list detail screen (Android `ShoppingItemsViewModel`).
@MainActor
@Observable
final class ListDetailViewModel {
    static let sampleListId = "sample-sunday-roast"
    /// How long the "<name> deleted" / Undo snackbar stays up: Android's
    /// `SnackbarDuration.Short`, which is 4 s in Material 3.
    static let undoSnackbarDuration: Duration = .seconds(4)

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

    /// Items in Android's DAO order (`ShoppingItemDao.getItemsByListId`): shop with nil
    /// last, then category id with nil last, then name.
    var sortedItems: [ShoppingItem] { items.sorted(by: Self.daoOrder) }
    var activeItems: [ShoppingItem] { sortedItems.filter { !$0.isPickedUp } }
    var completedItems: [ShoppingItem] { sortedItems.filter(\.isPickedUp) }
    var isEmpty: Bool { items.isEmpty }
    var totalCount: Int { items.count }
    var pickedUpCount: Int { completedItems.count }
    var progress: Double { totalCount == 0 ? 0 : Double(pickedUpCount) / Double(totalCount) }
    var percent: Int { Int(progress * 100) }
    var isAllDone: Bool { totalCount > 0 && pickedUpCount == totalCount }

    /// Active items grouped by shop, then category (Android `buildActiveSections`).
    /// Shops keep their first-seen order in `activeItems`; categories sort by name,
    /// case-insensitive, with the uncategorized bucket last. Items keep DAO order.
    var activeGroups: [ShopGroup] {
        var shops: [String?] = []
        var byShop: [String?: [ShoppingItem]] = [:]
        for item in activeItems {
            let shop = item.shop.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            if byShop[shop] == nil { shops.append(shop) }
            byShop[shop, default: []].append(item)
        }
        return shops.map { shop in
            let byCategory = Dictionary(grouping: byShop[shop] ?? []) { $0.categoryName }
            let categories = byCategory.keys.sorted(by: Self.namesNilLast).map {
                CategoryGroup(name: $0, items: byCategory[$0] ?? [])
            }
            return ShopGroup(shop: shop, categories: categories)
        }
    }

    /// Snackbar copy for the pending delete (Android `snackbar_deleted`, "%1$s deleted").
    var undoMessage: String? { pendingUndo.map { "\($0.item.name) deleted" } }

    /// The no-shop group gets a "General" header only when other shops exist.
    func showsShopHeader(_ group: ShopGroup) -> Bool {
        group.shop != nil || activeGroups.count > 1
    }

    private static func daoOrder(_ a: ShoppingItem, _ b: ShoppingItem) -> Bool {
        if (a.shop == nil) != (b.shop == nil) { return b.shop == nil }
        if let x = a.shop, let y = b.shop, x != y { return x < y }
        if (a.categoryId == nil) != (b.categoryId == nil) { return b.categoryId == nil }
        if let x = a.categoryId, let y = b.categoryId, x != y { return x < y }
        return a.name < b.name
    }

    private static func namesNilLast(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case let (x?, y?): x.caseInsensitiveCompare(y) == .orderedAscending
        case (_?, nil): true
        default: false
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
            categoryId: draft.categoryId,
            shop: shop.isEmpty ? nil : shop,
            note: note.isEmpty ? nil : note
        ))
        return true
    }
}
