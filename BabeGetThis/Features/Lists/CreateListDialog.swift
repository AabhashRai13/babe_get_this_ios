import SwiftUI

/// State and rules of the create / rename dialog (Android `CreateListDialog`). Pure, so it is
/// unit tested without a view.
struct CreateListDialogState: Equatable {
    /// What confirming asks the screen to do.
    enum Outcome: Equatable {
        case create(String)
        case rename(String)
    }

    static let maxNameLength = 40

    let currentName: String?
    private(set) var name: String

    /// Pass `currentName` for rename mode: the field starts with it and the button says Save.
    init(currentName: String? = nil) {
        self.currentName = currentName
        self.name = currentName ?? ""
    }

    var isEditMode: Bool { currentName != nil }
    var title: String { isEditMode ? "Rename List" : "New List" }
    var confirmTitle: String { isEditMode ? "Save" : "Create" }
    var fieldLabel: String { "List name" }
    var placeholder: String { "e.g. Weekly Groceries" }

    var isConfirmEnabled: Bool { !trimmed.isEmpty }

    /// "40/40", shown only once the limit is reached (Android supportingText).
    var counterText: String? {
        name.count >= Self.maxNameLength ? "\(name.count)/\(Self.maxNameLength)" : nil
    }

    /// Android `if (it.length <= 40) listName = it`: an over-long value is rejected
    /// wholesale, never clipped.
    mutating func type(_ value: String) {
        if value.count <= Self.maxNameLength { name = value }
    }

    /// The outcome with the trimmed name, or nil while the name is blank.
    func confirm() -> Outcome? {
        guard isConfirmEnabled else { return nil }
        return isEditMode ? .rename(trimmed) : .create(trimmed)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Modal name dialog. A custom card rather than `.alert`, because an alert's text field
/// can't enforce the 40-character limit or show the counter.
struct CreateListDialog: View {
    @State private var state: CreateListDialogState
    @FocusState private var isFocused: Bool
    let onDismiss: () -> Void
    let onConfirm: (CreateListDialogState.Outcome) -> Void

    init(currentName: String? = nil,
         onDismiss: @escaping () -> Void,
         onConfirm: @escaping (CreateListDialogState.Outcome) -> Void) {
        _state = State(initialValue: CreateListDialogState(currentName: currentName))
        self.onDismiss = onDismiss
        self.onConfirm = onConfirm
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 16) {
                Text(state.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 4) {
                    TextField(state.fieldLabel, text: Binding(get: { state.name }, set: { state.type($0) }),
                              prompt: Text(state.placeholder))
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(confirm)
                        .accessibilityLabel(state.fieldLabel)
                        .accessibilityIdentifier("lists.nameField")
                    if let counter = state.counterText {
                        Text(counter)
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .accessibilityIdentifier("lists.nameCounter")
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel", action: onDismiss)
                        .accessibilityIdentifier("lists.dialog.cancel")
                    Button(state.confirmTitle, action: confirm)
                        .fontWeight(.semibold)
                        .disabled(!state.isConfirmEnabled)
                        .accessibilityIdentifier("lists.dialog.confirm")
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(AppMetrics.screenPadding)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { isFocused = true }
    }

    private func confirm() {
        if let outcome = state.confirm() { onConfirm(outcome) }
    }
}
