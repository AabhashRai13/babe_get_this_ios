import Foundation

/// What the Google sheet hands back (Android `GoogleSignInToken`).
struct GoogleSignInToken: Equatable, Sendable {
    let idToken: String
    let rawNonce: String
}

/// Why the Google sheet could not produce a token (Android's `GoogleSignInOfflineException`,
/// `NoCredentialException`, `GetCredentialException`, `GoogleIdTokenParsingException`).
enum GoogleSheetFailure: Error, Equatable, Sendable {
    /// The requester refused to open the sheet because the device is offline.
    case offline
    /// No Google account on the device: the user's to fix, not a defect.
    case noAccount
    /// Sheet failure or unparseable credential (OAuth client misconfigured, ...): a defect to report.
    case failed(String)
}

/// Opens the Google sheet. Returns nil when the user closes it, which is not an error.
protocol LoginGoogleTokenRequester: Sendable {
    func request() async throws -> GoogleSignInToken?
}

/// The Google half of the auth repository (Android `AuthRepository.signInWithGoogle`).
protocol LoginGoogleAuthenticating: Sendable {
    func signInWithGoogle(idToken: String, rawNonce: String) async -> Result<AuthUser, AppError>
}

/// Sign-in telemetry. The event carries nothing: never attach the email.
protocol LoginAnalytics: Sendable {
    func trackAccountLoggedIn()
}

struct NoopLoginAnalytics: LoginAnalytics {
    func trackAccountLoggedIn() {}
}

/// Shared email check (Android `isValidEmail`): "something @ something . something", no spaces.
enum LoginEmailValidator {
    static func isValid(_ email: String) -> Bool {
        email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }
}
