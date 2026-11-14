import SwiftUI

/// Modal "Join a shared list" dialog (Android `JoinListDialog`). A custom card like
/// `CreateListDialog`, because an alert's text field can't normalise the code or show the error.
struct JoinListDialog: View {
    /// The code, owned by `ListsViewModel` so reopening starts empty.
    let model: JoinListViewModel
    /// What the field shows. Every edit is normalised and written back here, so the field never
    /// holds a seventh character, a space or a lowercase letter.
    @State private var text = ""
    @FocusState private var isFocused: Bool
    /// Why the last join failed, shown under the field.
    let error: String?
    /// A join is running: Join stays disabled until it ends.
    let isJoining: Bool
    let onDismiss: () -> Void
    let onJoin: (String) -> Void

    var body: some View {
        ZStack {
            AppColors.scrim
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 16) {
                Text(JoinListCopy.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 4) {
                    Text(JoinListCopy.fieldLabel)
                        .font(.caption)
                        .foregroundStyle(error == nil ? AppColors.textSecondary : AppColors.error)
                    TextField(JoinListCopy.fieldLabel, text: $text, prompt: Text(JoinListCopy.placeholder))
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .submitLabel(.join)
                        .onSubmit(join)
                        .accessibilityLabel(JoinListCopy.fieldLabel)
                        .accessibilityIdentifier("join.codeField")
                        .onChange(of: text) { _, new in
                            model.updateCode(new)
                            if text != model.code { text = model.code }
                        }
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(AppColors.error)
                            .accessibilityIdentifier("join.error")
                    }
                }
                HStack {
                    Spacer()
                    Button(JoinListCopy.cancel, action: onDismiss)
                        .accessibilityIdentifier("join.cancel")
                    Button(JoinListCopy.join, action: join)
                        .fontWeight(.semibold)
                        .disabled(!model.isJoinEnabled(isJoining: isJoining))
                        .accessibilityIdentifier("join.confirm")
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(AppMetrics.screenPadding)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear {
            text = model.code
            isFocused = true
        }
    }

    private func join() {
        guard model.isJoinEnabled(isJoining: isJoining) else { return }
        onJoin(model.code)
    }
}

#Preview {
    JoinListDialog(model: JoinListViewModel(), error: nil, isJoining: false, onDismiss: {}, onJoin: { _ in })
}
