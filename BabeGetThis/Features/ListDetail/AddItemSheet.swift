import SwiftUI

/// Add-item sheet: name and quantity required, then category, shop and note (Android `AddItemDialog`).
/// Labels and placeholders are Android's `strings.xml` copy.
struct AddItemSheet: View {
    /// Saves the draft (adds, or edits when `editing` is set); returns whether it was saved.
    let onAdd: @MainActor (ItemDraft, CategoryPickerModel) async -> Bool
    private let isEditMode: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ItemDraft
    @State private var picker: CategoryPickerModel
    @State private var isSaving = false

    /// Pass `editing` to open pre-filled in edit mode ("Edit Item" / "Save"), like Android's `editingItem`.
    /// `categorySource` creates the custom category when "Other" is picked.
    init(editing item: ShoppingItem? = nil, categorySource: (any CategoryPickerSource)? = nil,
         onAdd: @escaping @MainActor (ItemDraft, CategoryPickerModel) async -> Bool) {
        self.onAdd = onAdd
        isEditMode = item != nil
        _picker = State(initialValue: CategoryPickerModel(selectedId: item?.categoryId, source: categorySource))
        _draft = State(initialValue: item.map { ItemDraft(editing: $0) } ?? ItemDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledField(label: String(localized: .shoppingItemsNameHint), counter: draft.nameCounter) {
                        TextField(String(localized: .shoppingItemsNameHint), text: $draft.name)
                            .accessibilityIdentifier("add-item-name")
                    }
                    LabeledField(label: String(localized: .shoppingItemsQuantityHint)) {
                        TextField(String(localized: .shoppingItemsQuantityHint), text: $draft.quantity,
                                  prompt: Text(.shoppingItemsQuantityPlaceholder))
                            .accessibilityIdentifier("add-item-quantity")
                    }
                }
                Section {
                    CategoryPickerView(picker: picker)
                    LabeledField(label: String(localized: .shoppingItemsShop), counter: draft.shopCounter) {
                        TextField(String(localized: .shoppingItemsShop), text: $draft.shop,
                                  prompt: Text(.shoppingItemsShopPlaceholder))
                    }
                    LabeledField(label: String(localized: .shoppingItemsNote), counter: draft.noteCounter) {
                        TextField(String(localized: .shoppingItemsNote), text: $draft.note,
                                  prompt: Text(.shoppingItemsNotePlaceholder), axis: .vertical)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .onChange(of: draft.name) { _, new in
                if new.count > ItemDraft.nameLimit { draft.name = String(new.prefix(ItemDraft.nameLimit)) }
            }
            .onChange(of: draft.note) { _, new in
                if new.count > ItemDraft.noteLimit { draft.note = String(new.prefix(ItemDraft.noteLimit)) }
            }
            .onChange(of: draft.shop) { _, new in
                if new.count > ItemDraft.shopLimit { draft.shop = String(new.prefix(ItemDraft.shopLimit)) }
            }
            .navigationTitle(isEditMode ? Text(.shoppingItemsEditTitle) : Text(.shoppingItemsAddTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditMode ? String(localized: .save) : String(localized: .add)) {
                        isSaving = true
                        Task {
                            // Android keeps the dialog open when the save fails.
                            if await onAdd(draft, picker) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(!draft.isValid || isSaving)
                }
            }
        }
        .presentationDetents([.large])
        // Every category, live (Android `getAllCategories`), so custom ones are offered too.
        .task { await picker.observeCategories() }
    }
}

/// A form row with a visible label above its field, like Android's outlined text field
/// label, so the label stays on screen next to the placeholder.
private struct LabeledField<Field: View>: View {
    let label: String
    /// "n/limit", shown under the field once it is at its limit (Android `supportingText`).
    var counter: String?
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityHidden(true)
            field
            if let counter {
                Text(counter)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
