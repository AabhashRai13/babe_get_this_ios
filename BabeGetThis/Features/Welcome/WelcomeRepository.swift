import Foundation

/// Whether to open on the Welcome screen ("Sign in" / "Continue as guest", Android decision 008).
/// Shown only to a signed-out user who hasn't chosen yet. Signed-in users never see it, and
/// signing out asks again: signing out removes the account's lists, so it is a fresh start.
///
/// `isUpdateInstall` is true when this install is an update of an older version. Those users
/// have been using the app already, so they don't get a welcome.
final class WelcomeRepository: @unchecked Sendable {
    private static let welcomeDoneKey = "welcome_done"

    private let defaults: UserDefaults
    private let isUpdateInstall: () -> Bool

    init(defaults: UserDefaults = .standard, isUpdateInstall: @escaping () -> Bool = { false }) {
        self.defaults = defaults
        self.isUpdateInstall = isUpdateInstall
    }

    func shouldShowWelcome(authState: AuthState) -> Bool {
        authState == .unauthenticated && !isWelcomeDone()
    }

    /// "Continue as guest": the only choice that needs recording. Tapping Sign in doesn't: a
    /// signed-in user never sees Welcome, and backing out of Login must land on Welcome again.
    func markDone() {
        defaults.set(true, forKey: Self.welcomeDoneKey)
    }

    /// Explicit sign-out and account deletion.
    func reset() {
        defaults.set(false, forKey: Self.welcomeDoneKey)
    }

    /// The first answer is persisted rather than recomputed: a fresh install that gets an app
    /// update before anyone chose must still be offered the choice, even though it now looks
    /// like an update install.
    private func isWelcomeDone() -> Bool {
        if defaults.object(forKey: Self.welcomeDoneKey) == nil {
            defaults.set(isUpdateInstall(), forKey: Self.welcomeDoneKey)
        }
        return defaults.bool(forKey: Self.welcomeDoneKey)
    }
}
