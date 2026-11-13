import SwiftUI

/// Add-item sheet: name and quantity required, then category, shop and note (Android `AddItemDialog`).
/// Labels and placeholders are Android's `strings.xml` copy.
struct AddItemSheet: View {
    /// Saves the draft (adds, or edits when `editing` is set); returns whether it was saved.
    let onAdd: @MainActor (ItemDraft) async -> Bool
    private let isEditMode: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ItemDraft
    @State private var isSaving = false

    /// Pass `editing` to open pre-filled in edit mode ("Edit Item" / "Save"), like Android's `editingItem`.
    init(editing item: ShoppingItem? = nil, onAdd: @escaping @MainActor (ItemDraft) async -> Bool) {
        self.onAdd = onAdd
        isEditMode = item != nil
        _draft = State(initialValue: item.map { ItemDraft(editing: $0) } ?? ItemDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledField(label: "Item name", counter: draft.nameCounter) {
                        TextField("Item name", text: $draft.name)
                            .accessibilityIdentifier("add-item-name")
                    }
                    LabeledField(label: "Quantity (required)") {
                        TextField("Quantity (required)", text: $draft.quantity,
                                  prompt: Text("e.g. 2 large, slightly firm"))
                            .accessibilityIdentifier("add-item-quantity")
                    }
                }
                Section {
                    Picker("Category (optional)", selection: $draft.categoryId) {
                        Text("None").tag(String?.none)
                        ForEach(DefaultCategories.sortedByName, id: \.id) { category in
                            Text(category.name).tag(String?.some(category.id))
                        }
                    }
                    LabeledField(label: "Shop (optional)", counter: draft.shopCounter) {
                        TextField("Shop (optional)", text: $draft.shop,
                                  prompt: Text("e.g. Whole Foods, Costco"))
                    }
                    LabeledField(label: "Note (optional)", counter: draft.noteCounter) {
                        TextField("Note (optional)", text: $draft.note,
                                  prompt: Text("Leave a note to make it easier"), axis: .vertical)
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
            .navigationTitle(isEditMode ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditMode ? "Save" : "Add") {
                        isSaving = true
                        Task {
                            // Android keeps the dialog open when the save fails.
                            if await onAdd(draft) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(!draft.isValid || isSaving)
                }
            }
        }
        .presentationDetents([.large])
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
