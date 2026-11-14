import Foundation

extension ListDetailViewModel {
    /// Saves a new item with the category the picker resolves (creating a custom one for "Other").
    /// If the category can't be created the error shows and nothing is saved.
    func add(_ draft: ItemDraft, picker: CategoryPickerModel) async -> Bool {
        guard let withCategory = await resolvingCategory(draft, picker: picker) else { return false }
        return await add(withCategory)
    }

    /// Edit-mode counterpart of `add(_:picker:)`.
    func edit(_ id: String, with draft: ItemDraft, picker: CategoryPickerModel) async -> Bool {
        guard let withCategory = await resolvingCategory(draft, picker: picker) else { return false }
        return await edit(id, with: withCategory)
    }

    private func resolvingCategory(_ draft: ItemDraft, picker: CategoryPickerModel) async -> ItemDraft? {
        guard draft.isValid else { return nil }
        switch await picker.resolveCategoryId() {
        case .success(let categoryId):
            var resolved = draft
            resolved.categoryId = categoryId
            return resolved
        case .failure(let error):
            errorMessage = error.message
            return nil
        }
    }
}
