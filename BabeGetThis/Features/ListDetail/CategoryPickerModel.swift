import Foundation
import Observation

/// What the picker needs from `CategoryRepository` to create a custom category.
protocol CategoryPickerSource: Sendable {
    func addCategory(name: String) async throws -> Result<String, AppError>
}

extension CategoryRepository: CategoryPickerSource {}

extension AppContainer {
    /// Creates custom categories for the add/edit item sheet's "Other".
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

    let categories: [ProductCategory]
    private let source: (any CategoryPickerSource)?

    private(set) var selection: Selection
    var searchText: String
    var newCategoryName = ""

    /// `categories` default to the shipped defaults, alphabetical. `selectedId` pre-fills edit mode.
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
    func resolveCategoryId() async -> Result<String?, AppError> {
        switch selection {
        case .none: return .success(nil)
        case .category(let id): return .success(id)
        case .other:
            let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let source else { return .success(nil) }
            do {
                switch try await source.addCategory(name: name) {
                case .success(let id): return .success(id)
                case .failure(let error): return .failure(error)
                }
            } catch {
                return .failure(.unknown())
            }
        }
    }
}
