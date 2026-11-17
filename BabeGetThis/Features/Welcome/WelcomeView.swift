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
                Text(.appName)
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppColors.primary)
                    .padding(.top, 16)

                VStack(spacing: 16) {
                    // The account route is primary: it is what sharing and voice need.
                    // A Button, not a NavigationLink with a tap gesture: VoiceOver, Switch Control
                    // and keyboard activations skip gesture recognisers, and would go unreported.
                    Button(.welcomeSignIn) {
                        container.welcomeViewModel.onSignIn()
                        showSignIn = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("welcome.signIn")

                    Button(.welcomeContinueAsGuest) {
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
        // The same auth flow as the lists use, opened over Welcome (NAV-03): Close comes back
        // here with nothing persisted, and signing in lands on the lists, dropping Welcome.
        .sheet(isPresented: $showSignIn) {
            AuthSheet(flow: AuthFlow(start: .login, below: .welcome)) { exit in
                showSignIn = false
                container.session.leaveAuth(exit)
            }
        }
    }
}

/// Layered-circle cart mark shared by Welcome and Sign in. It grows with Dynamic Type alongside the
/// large title under it, keeping its proportions (104 / 76 / 32 pt at the default size).
struct BrandMark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 104

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.primaryContainer.opacity(0.3))
                .frame(width: size, height: size)
            Circle()
                .fill(AppColors.primaryContainer)
                .frame(width: size * 76 / 104, height: size * 76 / 104)
            Image(systemName: "cart")
                .font(.system(size: size * 32 / 104, weight: .regular))
                .foregroundStyle(AppColors.onPrimaryContainer)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack { WelcomeView() }
        .environment(AppContainer.preview)
}
