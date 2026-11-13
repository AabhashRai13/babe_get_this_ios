import Foundation
import Observation

/// What the user picked on Welcome (Android `WelcomeChoice`).
enum WelcomeChoice: String, Equatable, Sendable {
    case guest
    case signIn = "sign_in"
}

/// Reports the Welcome choice. Telemetry isn't wired yet, so the app uses `NoopWelcomeAnalytics`.
protocol WelcomeAnalytics: Sendable {
    func track(choice: WelcomeChoice)
}

struct NoopWelcomeAnalytics: WelcomeAnalytics {
    func track(choice: WelcomeChoice) {}
}

@Observable
@MainActor
final class WelcomeViewModel {
    @ObservationIgnored private let welcome: WelcomeRepository
    @ObservationIgnored private let analytics: WelcomeAnalytics
    @ObservationIgnored private let onGuestChosen: () -> Void

    init(welcome: WelcomeRepository, analytics: WelcomeAnalytics = NoopWelcomeAnalytics(),
         onGuestChosen: @escaping () -> Void = {}) {
        self.welcome = welcome
        self.analytics = analytics
        self.onGuestChosen = onGuestChosen
    }

    func onContinueAsGuest() {
        welcome.markDone()
        analytics.track(choice: .guest)
        onGuestChosen()
    }

    /// Welcome stays pending: backing out of Login lands here again.
    func onSignIn() {
        analytics.track(choice: .signIn)
    }
}
