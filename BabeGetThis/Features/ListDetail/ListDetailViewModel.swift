import Foundation
import Observation

/// What the list detail screen needs from `ShoppingItemRepository`. A seam so tests can
/// make a write fail; the app passes the repository itself.
protocol ListDetailItemsSource: Sendable {
    func itemsByListId(_ listId: String) -> AsyncThrowingStream<[StoredShoppingItem], any Error>
    func addItem(listId: String, name: String, quantity: String, categoryId: String?, shop: String?,
                 note: String?) async throws -> Result<String, AppError>
    func togglePickedUp(itemId: String, isPickedUp: Bool) async throws -> Result<Void, AppError>
    func updateItem(_ item: StoredShoppingItem) async throws -> Result<Void, AppError>
    func deleteItem(itemId: String) async throws -> Result<Void, AppError>
    func restoreItem(_ item: StoredShoppingItem) async throws -> Result<Void, AppError>
}

extension ShoppingItemRepository: ListDetailItemsSource {}

/// State of the list detail screen (Android `ShoppingItemsViewModel`): the list's items,
/// observed live from the database, and the writes that go through the item repository.
/// iOS v1 leaves out Android's lock, share, reminder, Got This and telemetry parts.
@MainActor
@Observable
final class ListDetailViewModel {
    /// How long the "<name> deleted" / Undo snackbar stays up: Android's
    /// `SnackbarDuration.Short`, which is 4 s in Material 3.
    static let undoSnackbarDuration: Duration = .seconds(4)

    let listId: String
    private let source: any ListDetailItemsSource
    private let haptics: any HapticPlaying

    /// The latest rows from the database, and the screen state derived from them once per emission.
    private(set) var storedItems: [StoredShoppingItem] = []
    private(set) var content = ListDetailContent(items: [])
    /// False until the database has answered, so an unloaded list doesn't flash the empty state.
    private(set) var hasLoaded = false
    /// The most recent delete, kept until a restore succeeds so a failed undo can be retried.
    private(set) var pendingUndo: StoredShoppingItem?
    /// Whether the "<name> deleted" / Undo snackbar is up.
    private(set) var isOfferingUndo = false
    /// A failed write or read, shown as a snackbar (Android `errorMessage`).
    var errorMessage: String?
    /// How many times the list went from not finished to finished (Android `ListJustCompleted`).
    private(set) var completionCount = 0
    /// nil until the first emission: opening an already-finished list must not celebrate.
    @ObservationIgnored private var wasAllDone: Bool?

    init(listId: String, source: any ListDetailItemsSource, haptics: any HapticPlaying = SystemHapticPlayer()) {
        self.listId = listId
        self.source = source
        self.haptics = haptics
    }

    // MARK: Derived state

    var items: [ShoppingItem] { content.items }
    var sortedItems: [ShoppingItem] { content.sortedItems }
    var activeItems: [ShoppingItem] { content.activeItems }
    var completedItems: [ShoppingItem] { content.completedItems }
    var activeGroups: [ShopGroup] { content.activeGroups }
    var isEmpty: Bool { content.items.isEmpty }
    var totalCount: Int { content.items.count }
    var pickedUpCount: Int { content.completedItems.count }
    var progress: Double { totalCount == 0 ? 0 : Double(pickedUpCount) / Double(totalCount) }
    var percent: Int { Int(progress * 100) }
    var isAllDone: Bool { totalCount > 0 && pickedUpCount == totalCount }

    /// Snackbar copy for the pending delete (Android `snackbar_deleted`, "%1$s deleted").
    var undoMessage: String? {
        guard isOfferingUndo, let pendingUndo else { return nil }
        return "\(pendingUndo.name) deleted"
    }

    /// The no-shop group gets a "General" header only when other shops exist.
    func showsShopHeader(_ group: ShopGroup) -> Bool {
        content.showsShopHeader(group)
    }

    // MARK: Observation

    /// Follows the list's items until the calling task is cancelled (the screen's `.task`).
    func observeItems() async {
        do {
            for try await rows in source.itemsByListId(listId) {
                apply(rows)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func apply(_ rows: [StoredShoppingItem]) {
        storedItems = rows
        content = ListDetailContent(items: rows.map { ShoppingItem($0) })
        hasLoaded = true
        // Only the transition counts, including deleting the last unticked item.
        if wasAllDone == false && isAllDone {
            completionCount += 1
            haptics.play(.success)
        }
        wasAllDone = isAllDone
    }

    // MARK: Actions

    /// Ticks or unticks the item. iOS v1 never writes `picked_up_at` (the repository doesn't).
    func toggle(_ id: String) async {
        guard let item = storedItems.first(where: { $0.id == id }) else { return }
        await run { try await source.togglePickedUp(itemId: id, isPickedUp: !item.isPickedUp) }
    }

    func delete(_ id: String) async {
        // Cached before deleting so Undo can restore it.
        let item = storedItems.first { $0.id == id }
        guard await run({ try await source.deleteItem(itemId: id) }) else { return }
        // Only offer Undo when there is something to restore.
        guard let item else { return }
        pendingUndo = item
        isOfferingUndo = true
    }

    /// The cache is cleared only once the item is safely back, so a failed restore can be retried.
    func undoDelete() async {
        guard let item = pendingUndo else { return }
        isOfferingUndo = false
        guard await run({ try await source.restoreItem(item) }) else { return }
        if pendingUndo?.id == item.id { pendingUndo = nil }
    }

    /// The snackbar timed out: the delete is final.
    func dismissUndo() {
        isOfferingUndo = false
        pendingUndo = nil
    }

    /// Adds the item when the draft is valid. Returns whether it was saved; on failure the
    /// error shows and the sheet stays open.
    func add(_ draft: ItemDraft) async -> Bool {
        guard draft.isValid else { return false }
        let shop = draft.shop.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return await run {
            try await source.addItem(
                listId: listId,
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                quantity: draft.quantity.trimmingCharacters(in: .whitespacesAndNewlines),
                categoryId: draft.categoryId,
                shop: shop.isEmpty ? nil : shop,
                note: note.isEmpty ? nil : note)
        }
    }

    /// Saves an edit from the dialog (Android `onEdit`). Only the dialog's fields change: the
    /// stored row keeps its id, list, created time and picked-up state. Returns whether it was saved.
    func edit(_ id: String, with draft: ItemDraft) async -> Bool {
        guard draft.isValid, var item = storedItems.first(where: { $0.id == id }) else { return false }
        let shop = draft.shop.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.quantity = draft.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        item.categoryId = draft.categoryId
        item.categoryName = nil
        item.shop = shop.isEmpty ? nil : shop
        item.note = note.isEmpty ? nil : note
        let updated = item
        return await run { try await source.updateItem(updated) }
    }

    /// Runs a repository write; a failure becomes `errorMessage`. Returns whether it succeeded.
    private func run<T>(_ write: () async throws -> Result<T, AppError>) async -> Bool {
        do {
            switch try await write() {
            case .success: return true
            case .failure(let error):
                errorMessage = error.message
                return false
            }
        } catch {
            // Only cancellation reaches here (safeCall maps everything else).
            return false
        }
    }

    private static func message(for error: any Error) -> String {
        SafeCall.map(error, onUnauthorized: { .unauthorized() }, onClientError: { _ in .unknown() }).message
    }
}

/// The screen's derived state, built once per database emission (Android `ShoppingItemsUiState`).
struct ListDetailContent: Equatable {
    let items: [ShoppingItem]
    /// Items in Android's DAO order (`ShoppingItemDao.getItemsByListId`): shop with nil
    /// last, then category id with nil last, then name.
    let sortedItems: [ShoppingItem]
    let activeItems: [ShoppingItem]
    let completedItems: [ShoppingItem]
    let activeGroups: [ShopGroup]

    init(items: [ShoppingItem]) {
        self.items = items
        sortedItems = items.sorted(by: Self.daoOrder)
        activeItems = sortedItems.filter { !$0.isPickedUp }
        completedItems = sortedItems.filter(\.isPickedUp)
        activeGroups = Self.groups(activeItems)
    }

    /// The no-shop group gets a "General" header only when other shops exist.
    func showsShopHeader(_ group: ShopGroup) -> Bool {
        group.shop != nil || activeGroups.count > 1
    }

    /// Active items grouped by shop, then category (Android `buildActiveSections`).
    /// Shops keep their first-seen order in `activeItems`; categories sort by name,
    /// case-insensitive, with the uncategorized bucket last. Items keep DAO order.
    private static func groups(_ activeItems: [ShoppingItem]) -> [ShopGroup] {
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
}
