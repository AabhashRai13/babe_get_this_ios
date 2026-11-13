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

    /// `forcedScreen` pins the screen for screenshots and previews (`-sampleData`).
    init(authState: AuthStateManager, welcome: WelcomeRepository, forcedScreen: StartScreen? = nil) {
        self.authState = authState
        self.welcome = welcome
        self.forcedScreen = forcedScreen
        signOutSubscription = authState.observeSignOuts { [weak self, welcome] in
            welcome.reset()
            Task { @MainActor in self?.welcomeRevision += 1 }
        }
    }

    var screen: StartScreen {
        _ = welcomeRevision
        return forcedScreen ?? StartScreen.resolve(authState: authState.authState, welcome: welcome)
    }

    /// Re-resolve after the Welcome choice was recorded.
    func refresh() { welcomeRevision += 1 }

    /// "Continue as guest" from a screen that doesn't go through `WelcomeViewModel`.
    func continueAsGuest() {
        welcome.markDone()
        refresh()
    }
}
