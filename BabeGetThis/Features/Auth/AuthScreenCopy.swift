/// Labels and layout of the auth screens (Android strings.xml). The views build their fields,
/// their scrolling body and their pinned footer from these lists and route every tap through the
/// `*ScreenTaps` types, so the AuthScreensTest port checks what the screens actually render.
enum LoginScreenCopy {
    static let email = "Email"                          // auth_email
    static let password = "Password"                    // auth_password
    static let signIn = "Sign in"                       // auth_sign_in
    static let forgotPassword = "Forgot password?"      // auth_forgot_password
    static let continueWithGoogle = "Continue with Google" // auth_continue_with_google
    static let noAccount = "Don't have an account?"     // auth_no_account
    static let signUp = "Sign up"                       // auth_sign_up

    /// The text fields in the form card, in order.
    static let fields: [LoginScreenField] = [.email, .password]
    /// What scrolls, top to bottom.
    static let scrollingContent: [LoginScreenElement] = [.brand, .header, .form, .forgotPassword, .signIn, .google, .apple]
    /// Pinned below the scroll so new users always see "Sign up" (Android: on a small phone the
    /// form alone fills the screen).
    static let pinnedFooter: [LoginScreenElement] = [.noAccount, .signUp]
}

enum LoginScreenField: Hashable, Sendable {
    case email, password

    var label: String {
        switch self {
        case .email: LoginScreenCopy.email
        case .password: LoginScreenCopy.password
        }
    }
}

/// One block of the login screen. `.form` is the card holding `LoginScreenCopy.fields`.
enum LoginScreenElement: Hashable, Sendable {
    case brand, header, form, forgotPassword, signIn, google, apple, noAccount, signUp

    /// The visible text, for the elements that have one of their own.
    var label: String? {
        switch self {
        case .forgotPassword: LoginScreenCopy.forgotPassword
        case .signIn: LoginScreenCopy.signIn
        case .google: LoginScreenCopy.continueWithGoogle
        case .noAccount: LoginScreenCopy.noAccount
        case .signUp: LoginScreenCopy.signUp
        case .brand, .header, .form, .apple: nil
        }
    }
}

/// What a tap on each login element does. Apple has its own system button and flow.
@MainActor
struct LoginScreenTaps {
    let viewModel: LoginViewModel
    let onRegister: () -> Void
    let onForgotPassword: () -> Void

    func tap(_ element: LoginScreenElement) {
        switch element {
        case .signIn: viewModel.login()
        case .google: viewModel.signInWithGoogle()
        case .forgotPassword: onForgotPassword()
        case .signUp: onRegister()
        case .brand, .header, .form, .apple, .noAccount: break
        }
    }
}

enum RegisterScreenCopy {
    static let name = AuthCopy.name                     // auth_name
    static let email = "Email"                          // auth_email
    static let password = "Password"                    // auth_password
    static let confirmPassword = "Confirm password"     // auth_confirm_password
    static let createAccount = "Create account"         // auth_register
    static let haveAccount = "Already have an account?" // auth_has_account
    static let signIn = "Sign in"                       // auth_sign_in

    /// The text fields in the form card, in order.
    static let fields: [RegisterScreenField] = [.name, .email, .password, .confirmPassword]
}

enum RegisterScreenField: Hashable, Sendable {
    case name, email, password, confirmPassword

    var label: String {
        switch self {
        case .name: RegisterScreenCopy.name
        case .email: RegisterScreenCopy.email
        case .password: RegisterScreenCopy.password
        case .confirmPassword: RegisterScreenCopy.confirmPassword
        }
    }
}

/// What a tap on each Register button does.
@MainActor
struct RegisterScreenTaps {
    enum Action: Sendable { case createAccount, signIn }

    let viewModel: RegisterViewModel
    let onLogin: () -> Void

    func tap(_ action: Action) {
        switch action {
        case .createAccount: viewModel.register()
        case .signIn: onLogin()
        }
    }
}

enum ForgotPasswordScreenCopy {
    static let email = "Email"                          // auth_email
    static let sendCode = "Send code"                   // auth_send_code
    static let code = "8-digit code"                    // auth_code
    static let newPassword = "New password"             // auth_new_password
    static let resetPassword = AuthCopy.resetPassword   // auth_reset_password

    /// The fields the screen shows: the email first, then (once the code is sent) the code and
    /// the new password.
    static func fields(codeSent: Bool) -> [ForgotPasswordField] {
        codeSent ? [.code, .newPassword] : [.email]
    }

    /// The step's primary action.
    static func primaryAction(codeSent: Bool) -> String {
        codeSent ? resetPassword : sendCode
    }
}

enum ForgotPasswordField: Hashable, Sendable {
    case email, code, newPassword

    var label: String {
        switch self {
        case .email: ForgotPasswordScreenCopy.email
        case .code: ForgotPasswordScreenCopy.code
        case .newPassword: ForgotPasswordScreenCopy.newPassword
        }
    }
}
