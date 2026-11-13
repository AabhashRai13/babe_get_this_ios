import SwiftUI

/// Email sign-up (Android `RegisterScreen`). Navigation is wired by the caller; the screen
/// itself never navigates.
struct RegisterView: View {
    @Bindable var viewModel: RegisterViewModel
    var onNavigateToLogin: () -> Void = {}

    @State private var passwordVisible = false
    @FocusState private var focus: Field?

    private enum Field { case name, email, password, confirm }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Create your account")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppColors.primary)
                        Text("Sync your lists with your partner")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 14) {
                        field(icon: "person", error: nil) {
                            TextField("Name", text: binding(\.name, viewModel.onNameChange))
                                .textContentType(.name)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .email }
                        }
                        field(icon: "envelope", error: viewModel.emailError) {
                            TextField("Email", text: binding(\.email, viewModel.onEmailChange))
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focus = .password }
                        }
                        field(icon: "lock", error: viewModel.passwordError, trailing: toggle) {
                            secure("Password", binding(\.password, viewModel.onPasswordChange))
                                .focused($focus, equals: .password)
                                .submitLabel(.next)
                                .onSubmit { focus = .confirm }
                        }
                        field(icon: "lock", error: viewModel.confirmPasswordError) {
                            secure("Confirm password", binding(\.confirmPassword, viewModel.onConfirmPasswordChange))
                                .focused($focus, equals: .confirm)
                                .submitLabel(.go)
                                .onSubmit { viewModel.register() }
                        }
                    }
                    .padding(20)
                    .background(AppColors.surfaceContainerLow,
                                in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))

                    Button { viewModel.register() } label: {
                        if viewModel.isLoading {
                            ProgressView().tint(AppColors.onPrimary)
                        } else {
                            Text("Create account").fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!viewModel.isFormValid || viewModel.isLoading)
                }
                .padding(.horizontal, AppMetrics.welcomePadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 4) {
                Text("Already have an account?")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                Button("Sign in", action: onNavigateToLogin)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.vertical, 8)
        }
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

    private var toggle: some View {
        Button(passwordVisible ? "Hide" : "Show") { passwordVisible.toggle() }
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppColors.primary)
    }

    @ViewBuilder
    private func secure(_ title: String, _ text: Binding<String>) -> some View {
        if passwordVisible {
            TextField(title, text: text).textInputAutocapitalization(.never).autocorrectionDisabled()
        } else {
            SecureField(title, text: text)
        }
    }

    private func field<Content: View>(icon: String, error: String?,
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

    private func binding(_ keyPath: KeyPath<RegisterViewModel, String>,
                         _ set: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: { viewModel[keyPath: keyPath] }, set: set)
    }
}
