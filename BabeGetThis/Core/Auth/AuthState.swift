import Foundation

/// The user's authentication status across the app (Android `AuthState`).
enum AuthState: Equatable, Sendable {
    /// App just launched, checking whether a saved session exists.
    case loading

    /// Logged in with a live token.
    case authenticated(userId: String)

    /// The session was lost (token expired or revoked) but the user never signed
    /// out. Their lists stay on screen and editable; only server features
    /// (sync, share, join, voice) wait for a fresh sign-in (Android decision 008).
    case sessionExpired(userId: String)

    /// No saved user: show Welcome / sign-in.
    case unauthenticated

    /// Whose lists this device shows: the account while signed in or after a
    /// lost session, nobody (guest lists) otherwise.
    var ownerId: String? {
        switch self {
        case .authenticated(let userId), .sessionExpired(let userId):
            userId
        case .loading, .unauthenticated:
            nil
        }
    }
}
