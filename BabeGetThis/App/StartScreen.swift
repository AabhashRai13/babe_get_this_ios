import Foundation
import Observation

/// Which screen the app opens on (NAV-02).
enum StartScreen: Equatable, Sendable {
    /// Auth state not restored yet: show a blank launch state, never Welcome or guest lists.
    case launch
    case welcome
    case lists

    static func resolve(authState: AuthState, welcome: WelcomeRepository) -> StartScreen {
        switch authState {
        case .loading:
            .launch
        case .authenticated, .sessionExpired:
            .lists
        case .unauthenticated:
            welcome.shouldShowWelcome(authState: authState) ? .welcome : .lists
        }
    }
}

/// Derives the start screen from `AuthStateManager` and the persisted guest choice, and sends
/// the app back to Welcome when an account signs out.
@Observable
@MainActor
final class StartSession {
    @ObservationIgnored private let authState: AuthStateManager
    @ObservationIgnored private let welcome: WelcomeRepository
    @ObservationIgnored private let forcedScreen: StartScreen?
    @ObservationIgnored private var signOutSubscription: AuthStateSubscription?
    /// Bumped whenever the persisted Welcome flag changes, so views re-resolve.
    private var welcomeRevision = 0
    /// Auth opened over Welcome ended in a sign-in. Android `leaveAuth` then navigates to the
    /// lists and pops Welcome itself, without waiting on the auth state; so does this. Not
    /// persisted (Android records nothing for "Sign in" either) and cleared by a sign-out.
    private var signedInFromWelcome = false

    /// `forcedScreen` pins the screen for screenshots and previews (`-sampleData`).
    init(authState: AuthStateManager, welcome: WelcomeRepository, forcedScreen: StartScreen? = nil) {
        self.authState = authState
        self.welcome = welcome
        self.forcedScreen = forcedScreen
        signOutSubscription = authState.observeSignOuts { [weak self, welcome] in
            welcome.reset()
            // Synchronous on the main thread, so the lists never show for a frame after sign-out.
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.didSignOut() }
            } else {
                Task { @MainActor in self?.didSignOut() }
            }
        }
    }

    private func didSignOut() {
        signedInFromWelcome = false
        welcomeRevision += 1
    }

    var screen: StartScreen {
        _ = welcomeRevision
        if let forcedScreen { return forcedScreen }
        let resolved = StartScreen.resolve(authState: authState.authState, welcome: welcome)
        return resolved == .welcome && signedInFromWelcome ? .lists : resolved
    }

    /// Leaving auth opened over Welcome (NAV-03, Android `closeAuth` / `leaveAuth`). Close comes
    /// back to Welcome with nothing recorded; a sign-in lands on the lists and drops Welcome.
    func leaveAuth(_ exit: AuthFlow.Exit) {
        if exit == .lists { signedInFromWelcome = true }
    }

    /// Re-resolve after the Welcome choice was recorded.
    func refresh() { welcomeRevision += 1 }

    /// "Continue as guest" from a screen that doesn't go through `WelcomeViewModel`.
    func continueAsGuest() {
        welcome.markDone()
        refresh()
    }
}
