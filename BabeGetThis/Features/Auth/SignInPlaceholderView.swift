import SwiftUI

/// Stand-in until the auth milestone (email/password + OTP reset, Google, Apple).
struct SignInPlaceholderView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        ContentUnavailableView {
            Label("Sign in is coming soon", systemImage: "person.crop.circle")
        } description: {
            Text("Email, Google and Apple sign-in arrive in the next milestone. You can use the app as a guest until then.")
        } actions: {
            Button("Continue as guest") { container.session.continueAsGuest() }
                .buttonStyle(.borderedProminent)
        }
        .background(AppColors.background)
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
    }
}
