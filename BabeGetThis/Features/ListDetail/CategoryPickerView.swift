import SwiftUI

/// Searchable category field for the add/edit item sheet (Android's category dropdown):
/// a search field, then None, the matching categories (or a no-match message), and Other.
struct CategoryPickerView: View {
    @Bindable var picker: CategoryPickerModel
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Category (optional)")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityHidden(true)
            HStack {
                if picker.isCreatingNewCategory {
                    Text(CategoryPickerModel.otherTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // The visible label above is hidden from VoiceOver, so name the field here.
                        .accessibilityLabel("Category (optional)")
                        .accessibilityValue(CategoryPickerModel.otherTitle)
                } else {
                    TextField("Category (optional)", text: Binding(
                        get: { picker.searchText },
                        set: { picker.searchChanged($0); isExpanded = true }),
                        prompt: Text(CategoryPickerModel.searchPlaceholder))
                        .accessibilityIdentifier("add-item-category")
                }
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Hide categories" : "Show categories")
            }
            if isExpanded {
                options
            }
            if picker.isCreatingNewCategory {
                TextField("New category name", text: $picker.newCategoryName)
                    .accessibilityIdentifier("add-item-new-category")
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        optionRow(CategoryPickerModel.noneTitle, isSelected: picker.selection == .none) {
            picker.selectNone()
            isExpanded = false
        }
        if let message = picker.noMatchMessage {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        } else {
            ForEach(picker.filteredCategories) { category in
                optionRow(category.name, isSelected: picker.selection == .category(category.id)) {
                    picker.select(category)
                    isExpanded = false
                }
            }
        }
        optionRow(CategoryPickerModel.otherTitle, isSelected: picker.selection == .other) {
            picker.selectOther()
            isExpanded = false
        }
    }

    private func optionRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        // VoiceOver says which option is the current choice.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
