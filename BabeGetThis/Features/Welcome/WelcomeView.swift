import SwiftUI

/// First launch, signed out: guest or account (Android WelcomeScreen, decision 008).
/// Guests keep lists on this phone only; an account syncs them, shares them and unlocks voice.
struct WelcomeView: View {
    @Environment(AppContainer.self) private var container
    @State private var showSignIn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BrandMark()
                Text("Babe, Get This")
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppColors.primary)
                    .padding(.top, 16)

                VStack(spacing: 16) {
                    // The account route is primary: it is what sharing and voice need.
                    // A Button, not a NavigationLink with a tap gesture: VoiceOver, Switch Control
                    // and keyboard activations skip gesture recognisers, and would go unreported.
                    Button("Sign in") {
                        container.welcomeViewModel.onSignIn()
                        showSignIn = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("welcome.signIn")

                    Button("Continue as guest") {
                        container.welcomeViewModel.onContinueAsGuest()
                    }
                    .buttonStyle(OutlinedButtonStyle())
                    .accessibilityIdentifier("welcome.guest")
                }
                .padding(.top, 40)
            }
            .padding(.horizontal, AppMetrics.welcomePadding)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppColors.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSignIn) { SignInPlaceholderView() }
    }
}

/// Layered-circle cart mark shared by Welcome and Sign in.
struct BrandMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.primaryContainer.opacity(0.3))
                .frame(width: 104, height: 104)
            Circle()
                .fill(AppColors.primaryContainer)
                .frame(width: 76, height: 76)
            Image(systemName: "cart")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(AppColors.onPrimaryContainer)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack { WelcomeView() }
        .environment(AppContainer.preview)
}
