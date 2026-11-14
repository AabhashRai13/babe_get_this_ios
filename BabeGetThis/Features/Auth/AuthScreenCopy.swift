/// Labels and layout of the auth screens (Android strings.xml), shared by the views and the
/// AuthScreensTest port, so the tests check what the screens actually render.
enum LoginScreenCopy {
    static let email = "Email"                          // auth_email
    static let password = "Password"                    // auth_password
    static let signIn = "Sign in"                       // auth_sign_in
    static let forgotPassword = "Forgot password?"      // auth_forgot_password
    static let continueWithGoogle = "Continue with Google" // auth_continue_with_google
    static let noAccount = "Don't have an account?"     // auth_no_account
    static let signUp = "Sign up"                       // auth_sign_up

    /// The text fields, in order.
    static let fields = [email, password]
    /// What scrolls. "Sign up" is pinned below it so new users always see it (Android: on a
    /// small phone the form alone fills the screen).
    static let scrollingContent = [email, password, forgotPassword, signIn, continueWithGoogle]
    static let pinnedFooter = [noAccount, signUp]
}

enum RegisterScreenCopy {
    static let name = AuthCopy.name                     // auth_name
    static let email = "Email"                          // auth_email
    static let password = "Password"                    // auth_password
    static let confirmPassword = "Confirm password"     // auth_confirm_password
    static let createAccount = "Create account"         // auth_register
    static let haveAccount = "Already have an account?" // auth_has_account
    static let signIn = "Sign in"                       // auth_sign_in

    static let fields = [name, email, password, confirmPassword]
}

enum ForgotPasswordScreenCopy {
    static let email = "Email"                          // auth_email
    static let sendCode = "Send code"                   // auth_send_code
    static let code = "8-digit code"                    // auth_code
    static let newPassword = "New password"             // auth_new_password
    static let resetPassword = AuthCopy.resetPassword   // auth_reset_password

    /// Step one: the email and "Send code".
    static let emailStepFields = [email]
    /// Step two, once the code is sent: the code and the new password.
    static let resetStepFields = [code, newPassword]

    static func fields(codeSent: Bool) -> [String] {
        codeSent ? resetStepFields : emailStepFields
    }
}
