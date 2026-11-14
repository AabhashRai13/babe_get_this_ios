import SwiftUI

/// Login, Register and Forgot password, presented as one sheet over the lists, a list or
/// Welcome. `AuthFlow` decides the back stack (NAV-03): Login and Register swap in place,
/// Forgot password pushes onto Login. Leaving reports where it lands: Close goes back to the
/// lists (or Welcome), any successful sign-in goes to the lists. The caller closes the sheet
/// and, over a list's screen or Welcome, routes there too.
struct AuthSheet: View {
    @Environment(AppContainer.self) private var container
    @State private var flow: AuthFlow
    let onExit: @MainActor @Sendable (AuthFlow.Exit) -> Void

    init(flow: AuthFlow, onExit: @escaping @MainActor @Sendable (AuthFlow.Exit) -> Void) {
        _flow = State(initialValue: flow)
        self.onExit = onExit
    }

    /// Over the lists or a list's screen (the auth prompt's "Sign in" / "Create account",
    /// AUTH-10, and the top bar's "Sign in").
    init(initialRoute: ListsViewModel.AuthRoute, below: AuthFlow.Below = .lists,
         onExit: @escaping @MainActor @Sendable (AuthFlow.Exit) -> Void) {
        self.init(flow: AuthFlow(start: initialRoute == .login ? .login : .register, below: below), onExit: onExit)
    }

    var body: some View {
        let close: @MainActor @Sendable () -> Void = { [flow, onExit] in onExit(flow.close()) }
        let succeed: @MainActor @Sendable () -> Void = { [flow, onExit] in onExit(flow.succeed()) }
        NavigationStack {
            Group {
                switch flow.root {
                case .login, .forgotPassword:
                    LoginScreen(container: container,
                                onRegister: { flow.showRegister() },
                                onForgotPassword: { flow.showForgotPassword() },
                                onClose: close, onSuccess: succeed)
                case .register:
                    RegisterScreen(container: container, onLogin: { flow.showLogin() },
                                   onClose: close, onSuccess: succeed)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { flow.isShowingForgotPassword },
                set: { if !$0, flow.isShowingForgotPassword { _ = flow.back() } }
            )) {
                ForgotPasswordScreen(container: container, onSuccess: succeed)
            }
        }
    }
}

/// Set by `RootView` on the lists' navigation stack: what leaving auth opened from a list's
/// screen does to that stack (NAV-03: Close and success both pop to the lists).
private struct LeaveAuthFromListKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (AuthFlow.Exit) -> Void = { _ in }
}

extension EnvironmentValues {
    var leaveAuthFromList: @MainActor @Sendable (AuthFlow.Exit) -> Void {
        get { self[LeaveAuthFromListKey.self] }
        set { self[LeaveAuthFromListKey.self] = newValue }
    }
}

// Each wrapper owns its view model, so swapping screens keeps nothing stale and a
// re-render never rebuilds one mid-request.

private struct LoginScreen: View {
    @State private var viewModel: LoginViewModel
    let onRegister: () -> Void
    let onForgotPassword: () -> Void
    let onClose: @MainActor @Sendable () -> Void

    init(container: AppContainer, onRegister: @escaping () -> Void, onForgotPassword: @escaping () -> Void,
         onClose: @escaping @MainActor @Sendable () -> Void, onSuccess: @escaping @MainActor @Sendable () -> Void) {
        let viewModel = container.makeLoginViewModel()
        viewModel.onLoginSuccess = onSuccess
        _viewModel = State(initialValue: viewModel)
        self.onRegister = onRegister
        self.onForgotPassword = onForgotPassword
        self.onClose = onClose
    }

    var body: some View {
        LoginView(viewModel: viewModel, onNavigateToRegister: onRegister,
                  onNavigateToForgotPassword: onForgotPassword, onClose: onClose)
    }
}

private struct RegisterScreen: View {
    @State private var viewModel: RegisterViewModel
    let onLogin: () -> Void
    let onClose: @MainActor @Sendable () -> Void

    init(container: AppContainer, onLogin: @escaping () -> Void,
         onClose: @escaping @MainActor @Sendable () -> Void, onSuccess: @escaping @MainActor @Sendable () -> Void) {
        let viewModel = container.makeRegisterViewModel()
        viewModel.onRegisterSuccess = onSuccess
        _viewModel = State(initialValue: viewModel)
        self.onLogin = onLogin
        self.onClose = onClose
    }

    var body: some View {
        RegisterView(viewModel: viewModel, onNavigateToLogin: onLogin)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        .tint(AppColors.textSecondary)
                }
            }
    }
}

private struct ForgotPasswordScreen: View {
    @State private var viewModel: ForgotPasswordViewModel

    init(container: AppContainer, onSuccess: @escaping @MainActor @Sendable () -> Void) {
        let viewModel = container.makeForgotPasswordViewModel()
        // A reset signs the user in, so it leaves auth entirely.
        viewModel.onResetSuccess = onSuccess
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ForgotPasswordView(viewModel: viewModel)
    }
}
