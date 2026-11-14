import SwiftUI

/// Email sign-up (Android `RegisterScreen`). Navigation is wired by the caller; the screen
/// itself never navigates.
struct RegisterView: View {
    @Bindable var viewModel: RegisterViewModel
    var onNavigateToLogin: () -> Void = {}

    @State private var passwordVisible = false
    @State private var confirmVisible = false
    @FocusState private var focus: Field?

    private enum Field { case name, email, password, confirm }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Android RegisterScreen: auth_welcome, app_name, auth_register_subtitle.
                    VStack(spacing: 4) {
                        Text(AuthCopy.welcome)
                            .font(.body)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(AuthCopy.appName)
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppColors.primary)
                        Text(AuthCopy.registerSubtitle)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(RegisterScreenCopy.fields, id: \.self) { formField($0) }
                    }
                    .padding(20)
                    .background(AppColors.surfaceContainerLow,
                                in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))

                    Button { taps.tap(.createAccount) } label: {
                        if viewModel.isLoading {
                            ProgressView().tint(AppColors.onPrimary)
                        } else {
                            Text(RegisterScreenCopy.createAccount).fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!viewModel.isFormValid || viewModel.isLoading)
                }
                .padding(.horizontal, AppMetrics.welcomePadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            // AUTH-02: errors show as a snackbar (Android `showSnackbar(it)` then `clearError()`),
            // so the form stays usable while the message is up. It hangs off the bottom of the
            // scroll, so it sits just above the pinned footer and never covers its link.
            .overlay(alignment: .bottom) {
                if let message = viewModel.errorMessage {
                    Snackbar(message: message)
                        .padding(.bottom, AppMetrics.screenPadding)
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

            HStack(spacing: 4) {
                Text(RegisterScreenCopy.haveAccount)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                Button(RegisterScreenCopy.signIn) { taps.tap(.signIn) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.vertical, 8)
        }
        .background(AppColors.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var taps: RegisterScreenTaps {
        RegisterScreenTaps(viewModel: viewModel, onLogin: onNavigateToLogin)
    }

    @ViewBuilder
    private func formField(_ formField: RegisterScreenField) -> some View {
        switch formField {
        case .name:
            field(icon: "person", error: nil) {
                TextField(formField.label, text: binding(\.name, viewModel.onNameChange))
                    .textContentType(.name)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
            }
        case .email:
            field(icon: "envelope", error: viewModel.emailError) {
                TextField(formField.label, text: binding(\.email, viewModel.onEmailChange))
                    .keyboardType(.emailAddress)
                    // .username, not .emailAddress: AutoFill saves the new password
                    // against this field (it would offer the owner's own address).
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
        case .password:
            field(icon: "lock", error: viewModel.passwordError,
                  trailing: toggle($passwordVisible, field: "password")) {
                secure(formField.label, binding(\.password, viewModel.onPasswordChange), visible: passwordVisible)
                    .focused($focus, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focus = .confirm }
            }
        case .confirmPassword:
            field(icon: "lock", error: viewModel.confirmPasswordError,
                  trailing: toggle($confirmVisible, field: "confirm password")) {
                secure(formField.label, binding(\.confirmPassword, viewModel.onConfirmPasswordChange),
                       visible: confirmVisible)
                    .focused($focus, equals: .confirm)
                    .submitLabel(.go)
                    .onSubmit { viewModel.register() }
            }
        }
    }

    /// Show/Hide for one password field. Swapping SecureField and TextField replaces the
    /// field, which drops focus, so the focused field gets it back after the swap.
    private func toggle(_ visible: Binding<Bool>, field: String) -> some View {
        Button(visible.wrappedValue ? "Hide" : "Show") {
            let kept = focus
            visible.wrappedValue.toggle()
            Task { @MainActor in focus = kept }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(AppColors.primary)
        .accessibilityLabel(AuthCopy.visibilityToggleLabel(isVisible: visible.wrappedValue, field: field))
    }

    /// Both branches get the new-password content type, so iOS offers a strong password,
    /// fills the confirm field and saves it, and never suggests text in the revealed field.
    private func secure(_ title: String, _ text: Binding<String>, visible: Bool) -> some View {
        Group {
            if visible {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }
        }
        .textContentType(.newPassword)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func field<Content: View>(icon: String, error: String?,
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

    private func binding(_ keyPath: KeyPath<RegisterViewModel, String>,
                         _ set: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: { viewModel[keyPath: keyPath] }, set: set)
    }
}
