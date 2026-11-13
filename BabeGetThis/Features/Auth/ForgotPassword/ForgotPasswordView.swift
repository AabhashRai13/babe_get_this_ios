import SwiftUI

/// Two-step password reset (Android `ForgotPasswordScreen`): email, then 8-digit code and new
/// password. Navigation is wired by the caller; the screen itself never navigates.
struct ForgotPasswordView: View {
    @Bindable var viewModel: ForgotPasswordViewModel

    @State private var passwordVisible = false
    @FocusState private var focus: Field?

    private enum Field { case email, code, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(AuthCopy.resetPassword)
                    .font(.title.bold())
                    .foregroundStyle(AppColors.primary)
                    .padding(.top, 24)
                // Step two names the address: there is no way back to the email field, so
                // this is where a typo shows before waiting for a code that never comes.
                Text(viewModel.codeSent ? AuthCopy.codeSent(to: viewModel.email) : AuthCopy.forgotSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)

                if viewModel.codeSent {
                    resetStep
                } else {
                    emailStep
                }
            }
            .padding(.horizontal, AppMetrics.welcomePadding)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let message = viewModel.errorMessage {
                Snackbar(message: message)
                    .padding(.bottom, AppMetrics.buttonHeight + AppMetrics.screenPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        AccessibilityNotification.Announcement(message).post()
                        try? await Task.sleep(for: SnackbarDuration.short)
                        guard !Task.isCancelled else { return }
                        withAnimation { viewModel.clearError() }
                    }
            }
        }
        .animation(.easeOut(duration: 0.25), value: viewModel.errorMessage)
        .onAppear { if !viewModel.codeSent { focus = .email } }
        // Step two exists to type the code; then the new password.
        .onChange(of: viewModel.codeSent) { _, sent in if sent { focus = .code } }
        .onChange(of: viewModel.code) { _, code in
            if focus == .code && code.count == ForgotPasswordViewModel.codeLength { focus = .password }
        }
        .toolbar {
            // The number pad has no Return key.
            ToolbarItemGroup(placement: .keyboard) {
                if focus == .code {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldBox(icon: "envelope", error: viewModel.emailError) {
                TextField("Email", text: Binding(get: { viewModel.email }, set: { viewModel.onEmailChange($0) }))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.go)
                    .onSubmit { viewModel.sendCode() }
            }
            Button { viewModel.sendCode() } label: {
                if viewModel.isLoading {
                    ProgressView().tint(AppColors.onPrimary)
                } else {
                    Text("Send code").fontWeight(.semibold)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!viewModel.isEmailValid || viewModel.isLoading)
        }
    }

    private var resetStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldBox(icon: "number", error: nil) {
                TextField("8-digit code", text: Binding(get: { viewModel.code }, set: { viewModel.onCodeChange($0) }))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focus, equals: .code)
            }
            fieldBox(icon: "lock", error: viewModel.passwordError, trailing: toggle) {
                let text = Binding(get: { viewModel.newPassword }, set: { viewModel.onNewPasswordChange($0) })
                Group {
                    if passwordVisible {
                        TextField("New password", text: text)
                    } else {
                        SecureField("New password", text: text)
                    }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { viewModel.resetPassword() }
            }
            Button { viewModel.resetPassword() } label: {
                if viewModel.isLoading {
                    ProgressView().tint(AppColors.onPrimary)
                } else {
                    Text("Reset password").fontWeight(.semibold)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!viewModel.isResetFormValid || viewModel.isLoading)
        }
    }

    /// The swap replaces the field and drops focus, so a focused field gets it back.
    private var toggle: some View {
        Button(passwordVisible ? "Hide" : "Show") {
            let kept = focus
            passwordVisible.toggle()
            Task { @MainActor in focus = kept }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(AppColors.primary)
        .accessibilityLabel(AuthCopy.visibilityToggleLabel(isVisible: passwordVisible))
    }

    private func fieldBox<Content: View>(icon: String, error: String?,
                                         trailing: some View = EmptyView(),
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Decorative, like Android's contentDescription = null.
                Image(systemName: icon).foregroundStyle(AppColors.primary).accessibilityHidden(true)
                content()
                trailing
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(AppColors.surface,
                        in: RoundedRectangle(cornerRadius: AppMetrics.tileRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppMetrics.tileRadius, style: .continuous)
                    .strokeBorder(error != nil ? AppColors.error : AppColors.outline.opacity(0.5), lineWidth: 1)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(AppColors.error)
            }
        }
    }
}
