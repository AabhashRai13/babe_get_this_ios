import Foundation
import Observation

/// What the picker needs from `CategoryRepository`: every category, live, and creating a
/// custom one.
protocol CategoryPickerSource: Sendable {
    /// Defaults plus user-created, A→Z (Android `getAllCategories`).
    func allCategories() -> AsyncThrowingStream<[ProductCategory], any Error>
    func addCategory(name: String) async throws -> Result<String, AppError>
}

extension CategoryRepository: CategoryPickerSource {}

extension AppContainer {
    /// Lists every category for the add/edit item sheet and creates custom ones for "Other".
    var categoryPickerSource: any CategoryPickerSource {
        CategoryRepository(dao: database.categories, safeCall: SafeCall(reporter: SilentAppErrorReporter()))
    }
}

/// State of the add/edit item sheet's category picker (Android `AddItemDialog` category
/// dropdown): a case-insensitive search over the categories, "None", and "Other", which
/// asks for a new category name that is created when the item is saved.
@MainActor
@Observable
final class CategoryPickerModel {
    enum Selection: Equatable {
        case none
        case category(String)
        /// "Other": a new custom category named `newCategoryName`.
        case other
    }

    /// Android `category_none` / `category_other`.
    static let noneTitle = "None"
    static let otherTitle = "Other"
    static let searchPlaceholder = "Search or select category"
    static let newCategoryLabel = "New category name"

    /// Every category, A→Z. Starts with what was passed (or the shipped defaults) and follows
    /// the source's live list once `observeCategories()` runs, so custom categories appear.
    private(set) var categories: [ProductCategory]
    private let source: (any CategoryPickerSource)?

    private(set) var selection: Selection
    var searchText: String
    var newCategoryName = ""

    /// `categories` default to the shipped defaults, alphabetical, until the live list arrives.
    /// `selectedId` pre-fills edit mode.
    init(categories: [ProductCategory]? = nil, selectedId: String? = nil, source: (any CategoryPickerSource)? = nil) {
        let all = categories ?? DefaultCategories.sortedByName.map { $0.toDomain() }
        self.categories = all
        self.source = source
        if let selectedId {
            selection = .category(selectedId)
            searchText = all.first { $0.id == selectedId }?.name ?? ""
        } else {
            selection = .none
            searchText = ""
        }
    }

    /// Follows the source's categories until cancelled (the sheet's `.task`). An item edited
    /// with a custom category gets its name in the field once that category is known.
    func observeCategories() async {
        guard let source else { return }
        do {
            for try await fresh in source.allCategories() {
                categories = fresh
                if case .category(let id) = selection, searchText.isEmpty,
                   let match = fresh.first(where: { $0.id == id }) {
                    searchText = match.name
                }
            }
        } catch {
            // Keep the categories already shown; the picker still works with them.
        }
    }

    // MARK: Filtering

    /// Android: blank search shows everything, otherwise `name.contains(text, ignoreCase = true)`.
    static func filter(_ categories: [ProductCategory], matching query: String) -> [ProductCategory] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return categories }
        return categories.filter { $0.name.range(of: query, options: .caseInsensitive) != nil }
    }

    /// Android `shopping_items_category_no_match`.
    static func noMatchMessage(for query: String) -> String {
        "No categories match \"\(query)\""
    }

    var filteredCategories: [ProductCategory] { Self.filter(categories, matching: searchText) }

    /// Shown (instead of the list) when a non-blank search matches nothing.
    var noMatchMessage: String? {
        filteredCategories.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.noMatchMessage(for: searchText) : nil
    }

    // MARK: Selection

    var isCreatingNewCategory: Bool { selection == .other }

    var selectedCategoryId: String? {
        if case .category(let id) = selection { return id }
        return nil
    }

    func selectNone() {
        selection = .none
        searchText = ""
    }

    func select(_ category: ProductCategory) {
        selection = .category(category.id)
        searchText = category.name
    }

    func selectOther() {
        selection = .other
        searchText = ""
    }

    /// Typing in the field drops the current selection, like Android.
    func searchChanged(_ text: String) {
        searchText = text
        selection = .none
    }

    // MARK: Saving

    /// The category id to save the item with. "Other" with a non-blank name creates the category
    /// through the repository first (Android `onCreateCategory`); "Other" with a blank name saves none.
    /// A name that already exists (trimmed, ignoring case) reuses that category instead of adding
    /// a second one. Once resolved, the category is selected, so a retry after a failed save
    /// reuses it.
    func resolveCategoryId() async -> Result<String?, AppError> {
        switch selection {
        case .none: return .success(nil)
        case .category(let id): return .success(id)
        case .other:
            let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let source else { return .success(nil) }
            if let existing = Self.existing(named: name, in: categories) {
                select(existing)
                return .success(existing.id)
            }
            do {
                switch try await source.addCategory(name: name) {
                case .success(let id):
                    select(ProductCategory(id: id, name: name, isDefault: false))
                    return .success(id)
                case .failure(let error): return .failure(error)
                }
            } catch {
                return .failure(.unknown())
            }
        }
    }

    /// Kotlin `equals(ignoreCase = true)` on the trimmed names, the same case rule as the search.
    static func existing(named name: String, in categories: [ProductCategory]) -> ProductCategory? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return categories.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(wanted) == .orderedSame
        }
    }
}
