/// Copy shared by the sign-up and reset screens, from Android strings.xml.
enum AuthCopy {
    static let welcome = "Welcome to"                                            // auth_welcome
    static let appName = "Babe, Get This"                                         // app_name
    static let registerSubtitle = "Create an account to start sharing lists"      // auth_register_subtitle
    static let name = "Your name"                                                 // auth_name
    static let resetPassword = "Reset password"                                   // auth_reset_password
    static let forgotSubtitle = "Enter your email and we'll send you an 8-digit code" // auth_forgot_subtitle

    /// auth_code_sent, with the address the code went to, so a typo shows before the wait.
    static func codeSent(to email: String) -> String {
        "Enter the code we sent to \(email) and choose a new password"
    }

    /// VoiceOver label of a Show/Hide button, naming the field it reveals.
    static func visibilityToggleLabel(isVisible: Bool, field: String = "password") -> String {
        "\(isVisible ? "Hide" : "Show") \(field)"
    }
}
