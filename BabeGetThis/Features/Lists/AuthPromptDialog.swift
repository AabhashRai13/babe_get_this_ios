import SwiftUI

/// Copy for a "sign in to continue" gate. Title and body are required so each gate names
/// itself (Android AuthPromptDialog; strings voice_auth_* and share_auth_*).
struct AuthPromptContent: Equatable {
    let title: String
    let body: String

    static let voice = AuthPromptContent(
        title: "Sign in to use voice",
        body: "Create an account to capture shopping lists by voice.")
    static let share = AuthPromptContent(
        title: "Sign in to share",
        body: "Create an account to share lists with your partner and sync across devices.")

    static let confirmTitle = "Sign in"
    static let dismissTitle = "Create account"
}

/// Alert-style dialog: "Sign in" (primary) and "Create account". Either button also dismisses.
struct AuthPromptDialog: View {
    let content: AuthPromptContent
    let onLogin: () -> Void
    let onRegister: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 16) {
                Text(content.title)
                    .font(.title3.bold())
                    .foregroundStyle(AppColors.textPrimary)
                Text(content.body)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                HStack(spacing: 8) {
                    Spacer()
                    Button(AuthPromptContent.dismissTitle) {
                        onDismiss()
                        onRegister()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .accessibilityIdentifier("authPrompt.register")
                    Button(AuthPromptContent.confirmTitle) {
                        onDismiss()
                        onLogin()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("authPrompt.login")
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

#Preview {
    AuthPromptDialog(content: .voice, onLogin: {}, onRegister: {}, onDismiss: {})
}
