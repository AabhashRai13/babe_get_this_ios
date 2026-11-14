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
    /// What the field shows. The field writes through `edit(_:)`; `enforceLimit()` then puts an
    /// over-long value back, so a rejected value really changes and the field re-syncs.
    private(set) var name: String
    /// The last value within the limit, recorded on every edit as it arrives. A rejected value
    /// goes back to this, never to the value SwiftUI saw at its previous update: several keys can
    /// land before one update runs, so that value may itself be over the limit, or miss a key.
    private var keptName: String

    /// Pass `currentName` for rename mode: the field starts with it and the button says Save.
    init(currentName: String? = nil) {
        self.currentName = currentName
        self.name = currentName ?? ""
        self.keptName = name
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
        edit(value)
        enforceLimit()
    }

    /// The field's binding: the field has already taken the value, so `name` takes it too (a
    /// later revert is then a real change), and a value within the limit is remembered at once.
    mutating func edit(_ value: String) {
        name = value
        if value.count <= Self.maxNameLength { keptName = value }
    }

    /// After the field's edits are applied (`onChange`): an over-long value (typed or pasted)
    /// goes back to the last value within the limit, never clipped.
    mutating func enforceLimit() {
        if name.count > Self.maxNameLength { name = keptName }
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
    /// The confirmed write is in flight: Create stays disabled until it ends.
    let isBusy: Bool
    let onDismiss: () -> Void
    let onConfirm: (CreateListDialogState.Outcome) -> Void

    init(currentName: String? = nil,
         isBusy: Bool = false,
         onDismiss: @escaping () -> Void,
         onConfirm: @escaping (CreateListDialogState.Outcome) -> Void) {
        _state = State(initialValue: CreateListDialogState(currentName: currentName))
        self.isBusy = isBusy
        self.onDismiss = onDismiss
        self.onConfirm = onConfirm
    }

    var body: some View {
        ZStack {
            AppColors.scrim
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 16) {
                Text(state.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 4) {
                    TextField(state.fieldLabel, text: Binding(get: { state.name }, set: { state.edit($0) }),
                              prompt: Text(state.placeholder))
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(confirm)
                        .accessibilityLabel(state.fieldLabel)
                        .accessibilityIdentifier("lists.nameField")
                        .onChange(of: state.name) { state.enforceLimit() }
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
                        .disabled(!state.isConfirmEnabled || isBusy)
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
        guard !isBusy else { return }
        if let outcome = state.confirm() { onConfirm(outcome) }
    }
}
