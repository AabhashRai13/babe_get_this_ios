import SwiftUI

/// Two-step password reset (Android `ForgotPasswordScreen`): email, then 8-digit code and new
/// password. Navigation is wired by the caller; the screen itself never navigates.
struct ForgotPasswordView: View {
    @Bindable var viewModel: ForgotPasswordViewModel

    @State private var passwordVisible = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reset your password")
                    .font(.title.bold())
                    .foregroundStyle(AppColors.primary)
                    .padding(.top, 24)
                Text(viewModel.codeSent
                     ? "Enter the 8-digit code we emailed you and choose a new password."
                     : "Enter your email and we'll send you an 8-digit code.")
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
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldBox(icon: "envelope", error: viewModel.emailError) {
                TextField("Email", text: Binding(get: { viewModel.email }, set: { viewModel.onEmailChange($0) }))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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

    private var toggle: some View {
        Button(passwordVisible ? "Hide" : "Show") { passwordVisible.toggle() }
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppColors.primary)
    }

    private func fieldBox<Content: View>(icon: String, error: String?,
                                         trailing: some View = EmptyView(),
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon).foregroundStyle(AppColors.primary)
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
