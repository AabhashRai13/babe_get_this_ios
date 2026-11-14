import AuthenticationServices
import SwiftUI

/// Email / Google / Apple sign-in (Android `LoginScreen`). Navigation is wired by the caller
/// through the closures; the screen itself never navigates.
struct LoginView: View {
    @Bindable var viewModel: LoginViewModel
    @Environment(\.colorScheme) private var colorScheme
    var onNavigateToRegister: () -> Void = {}
    var onNavigateToForgotPassword: () -> Void = {}
    var onClose: () -> Void = {}

    @State private var passwordVisible = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    BrandMark().padding(.top, 24)
                    header
                    formCard.padding(.top, 16)
                    forgotPassword
                    signInButton.padding(.top, 12)
                    googleButton.padding(.top, 12)
                    appleButton.padding(.top, 12)
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

            // Pinned below the scroll (LoginScreenCopy.pinnedFooter), never scrolled out of view.
            HStack(spacing: 4) {
                Text(LoginScreenCopy.noAccount)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                Button(LoginScreenCopy.signUp, action: onNavigateToRegister)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.vertical, 8)
        }
        .background(AppColors.background)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
                    .tint(AppColors.textSecondary)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Welcome to")
                .font(.body)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 12)
            Text("Babe, Get This")
                .font(.largeTitle.bold())
                .foregroundStyle(AppColors.primary)
            Text("Sign in to sync your lists with your partner")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 4)
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "envelope").foregroundStyle(AppColors.primary)
                    TextField(LoginScreenCopy.email, text: emailBinding)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }
                .modifier(LoginFieldChrome(isError: viewModel.emailError != nil))
                if let error = viewModel.emailError {
                    Text(error).font(.caption).foregroundStyle(AppColors.error)
                }
            }
            HStack {
                Image(systemName: "lock").foregroundStyle(AppColors.primary)
                Group {
                    if passwordVisible {
                        TextField(LoginScreenCopy.password, text: passwordBinding)
                    } else {
                        SecureField(LoginScreenCopy.password, text: passwordBinding)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { viewModel.login() }
                Button(passwordVisible ? "Hide" : "Show") { passwordVisible.toggle() }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColors.primary)
            }
            .modifier(LoginFieldChrome(isError: false))
        }
        .padding(20)
        .background(AppColors.surfaceContainerLow,
                    in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
    }

    private var forgotPassword: some View {
        HStack {
            Spacer()
            Button(LoginScreenCopy.forgotPassword, action: onNavigateToForgotPassword)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.primary)
        }
        .padding(.top, 8)
    }

    // Each button shows the spinner only for its own path; all three stay disabled while any
    // sign-in runs.
    private var signInButton: some View {
        Button { viewModel.login() } label: {
            if viewModel.showsSpinner(for: .email) {
                ProgressView().tint(AppColors.onPrimary)
            } else {
                Text(LoginScreenCopy.signIn).fontWeight(.semibold)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!viewModel.isEmailSignInEnabled)
    }

    private var googleButton: some View {
        Button { viewModel.signInWithGoogle() } label: {
            if viewModel.showsSpinner(for: .google) {
                ProgressView()
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "g.circle")
                    Text(LoginScreenCopy.continueWithGoogle).fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(OutlinedButtonStyle())
        .disabled(viewModel.isLoading)
    }

    /// AUTH-06: next to Google at the same size, black in light mode and white in dark.
    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            AppleIdTokenSignIn.configure(request, nonceHash: viewModel.prepareAppleSignIn())
        } onCompletion: { result in
            viewModel.completeAppleSignIn(AppleAuthorizationOutcome(result))
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(maxWidth: .infinity, minHeight: AppMetrics.buttonHeight, maxHeight: AppMetrics.buttonHeight)
        .overlay {
            // Apple's button can't show a spinner itself: cover its label with one, in its colours.
            if viewModel.showsSpinner(for: .apple) {
                ZStack {
                    colorScheme == .dark ? Color.white : Color.black
                    ProgressView().tint(colorScheme == .dark ? Color.black : Color.white)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous))
        // `.disabled` doesn't dim Apple's button, so dim it while another path runs.
        .opacity(viewModel.isLoading && !viewModel.showsSpinner(for: .apple) ? 0.5 : 1)
        .disabled(viewModel.isLoading)
    }

    private var emailBinding: Binding<String> {
        Binding(get: { viewModel.email }, set: { viewModel.onEmailChange($0) })
    }

    private var passwordBinding: Binding<String> {
        Binding(get: { viewModel.password }, set: { viewModel.onPasswordChange($0) })
    }
}

private struct LoginFieldChrome: ViewModifier {
    let isError: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(AppColors.surface,
                        in: RoundedRectangle(cornerRadius: AppMetrics.tileRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppMetrics.tileRadius, style: .continuous)
                    .strokeBorder(isError ? AppColors.error : AppColors.outline.opacity(0.5), lineWidth: 1)
            }
    }
}
