import SwiftUI

/// Login and Register presented over the lists, for the auth prompt's "Sign in" and
/// "Create account" (AUTH-10). Each screen's link swaps to the other; "Forgot password?"
/// pushes the reset screen. Any successful sign-in closes the sheet. The app-wide auth
/// navigation (back stack, account control, session banner) is F24.
struct AuthSheet: View {
    @Environment(AppContainer.self) private var container
    @State private var route: ListsViewModel.AuthRoute
    @State private var showsForgotPassword = false
    let onDone: @MainActor @Sendable () -> Void

    init(initialRoute: ListsViewModel.AuthRoute, onDone: @escaping @MainActor @Sendable () -> Void) {
        _route = State(initialValue: initialRoute)
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Group {
                switch route {
                case .login:
                    LoginScreen(container: container,
                                onRegister: { route = .register },
                                onForgotPassword: { showsForgotPassword = true },
                                onDone: onDone)
                case .register:
                    RegisterScreen(container: container, onLogin: { route = .login }, onDone: onDone)
                }
            }
            .navigationDestination(isPresented: $showsForgotPassword) {
                ForgotPasswordScreen(container: container, onDone: onDone)
            }
        }
    }
}

// Each wrapper owns its view model, so swapping screens keeps nothing stale and a
// re-render never rebuilds one mid-request.

private struct LoginScreen: View {
    @State private var viewModel: LoginViewModel
    let onRegister: () -> Void
    let onForgotPassword: () -> Void

    init(container: AppContainer, onRegister: @escaping () -> Void,
         onForgotPassword: @escaping () -> Void, onDone: @escaping @MainActor @Sendable () -> Void) {
        let viewModel = container.makeLoginViewModel()
        viewModel.onLoginSuccess = onDone
        _viewModel = State(initialValue: viewModel)
        self.onRegister = onRegister
        self.onForgotPassword = onForgotPassword
        self.onDone = onDone
    }

    let onDone: @MainActor @Sendable () -> Void

    var body: some View {
        LoginView(viewModel: viewModel, onNavigateToRegister: onRegister,
                  onNavigateToForgotPassword: onForgotPassword, onClose: onDone)
    }
}

private struct RegisterScreen: View {
    @State private var viewModel: RegisterViewModel
    let onLogin: () -> Void
    let onDone: @MainActor @Sendable () -> Void

    init(container: AppContainer, onLogin: @escaping () -> Void, onDone: @escaping @MainActor @Sendable () -> Void) {
        let viewModel = container.makeRegisterViewModel()
        viewModel.onRegisterSuccess = onDone
        _viewModel = State(initialValue: viewModel)
        self.onLogin = onLogin
        self.onDone = onDone
    }

    var body: some View {
        RegisterView(viewModel: viewModel, onNavigateToLogin: onLogin)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDone) { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        .tint(AppColors.textSecondary)
                }
            }
    }
}

private struct ForgotPasswordScreen: View {
    @State private var viewModel: ForgotPasswordViewModel

    init(container: AppContainer, onDone: @escaping @MainActor @Sendable () -> Void) {
        let viewModel = container.makeForgotPasswordViewModel()
        // A reset signs the user in.
        viewModel.onResetSuccess = onDone
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ForgotPasswordView(viewModel: viewModel)
    }
}

/// Google sign-in until F23 wires the real sheet: the button fails with the usual message.
struct GoogleSignInNotWired: LoginGoogleTokenRequester, LoginGoogleAuthenticating {
    func request() async throws -> GoogleSignInToken? {
        throw GoogleSheetFailure.failed("Google sign-in is not wired yet (F23)")
    }

    func signInWithGoogle(idToken: String, rawNonce: String) async -> Result<AuthUser, AppError> {
        .failure(.unknown(AuthErrorMapper.googleSignInFailed))
    }
}
