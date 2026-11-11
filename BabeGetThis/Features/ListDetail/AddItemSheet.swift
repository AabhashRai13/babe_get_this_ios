import SwiftUI

/// Add-item sheet: name and quantity required, then category, shop and note (Android `AddItemDialog`).
struct AddItemSheet: View {
    let onAdd: (ItemDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ItemDraft()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item name", text: $draft.name)
                        .accessibilityIdentifier("add-item-name")
                    TextField("Quantity (e.g. 2 kg)", text: $draft.quantity)
                        .accessibilityIdentifier("add-item-quantity")
                } footer: {
                    Text("Name and quantity are required.")
                }
                Section {
                    Picker("Category", selection: $draft.category) {
                        Text("None").tag(String?.none)
                        ForEach(ListDetailViewModel.categories, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    TextField("Shop (optional)", text: $draft.shop)
                    TextField("Note (optional)", text: $draft.note, axis: .vertical)
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
            .navigationTitle("Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .presentationDetents([.large])
    }
}
