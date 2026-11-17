/// Copy shared by the sign-up and reset screens: Android strings.xml keys in Localizable.xcstrings.
enum AuthCopy {
    static var welcome: String { String(localized: .authWelcome) }
    static var appName: String { String(localized: .appName) }
    static var registerSubtitle: String { String(localized: .authRegisterSubtitle) }
    static var name: String { String(localized: .authName) }
    static var resetPassword: String { String(localized: .authResetPassword) }
    static var forgotSubtitle: String { String(localized: .authForgotSubtitle) }

    /// auth_code_sent, with the address the code went to, so a typo shows before the wait.
    static func codeSent(to email: String) -> String {
        String(localized: .authCodeSent(email))
    }

    /// The password fields that have a Show/Hide button.
    enum PasswordField: Sendable {
        case password, confirmPassword
    }

    /// The Show/Hide button's visible text.
    static func visibilityToggleTitle(isVisible: Bool) -> String {
        isVisible ? String(localized: .authHide) : String(localized: .authShow)
    }

    /// VoiceOver label of a Show/Hide button, naming the field it reveals. Whole phrases, so a
    /// translation never has to glue a verb to a field name.
    static func visibilityToggleLabel(isVisible: Bool, field: PasswordField = .password) -> String {
        switch (field, isVisible) {
        case (.password, false): String(localized: .authShowPassword)
        case (.password, true): String(localized: .authHidePassword)
        case (.confirmPassword, false): String(localized: .authShowConfirmPassword)
        case (.confirmPassword, true): String(localized: .authHideConfirmPassword)
        }
    }
}
