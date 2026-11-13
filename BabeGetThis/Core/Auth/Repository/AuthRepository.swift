import Foundation

/// The signed-in user as the app sees it (Android `core/auth/model/User`).
struct AuthUser: Equatable, Sendable {
    let id: String
    let email: String
    let name: String
}

/// The two outcomes of a *successful* sign-up (Android `RegisterResult`):
/// - `signedIn`: "Confirm email" is OFF, so a session exists and the user is in now.
/// - `confirmationRequired`: "Confirm email" is ON, so the user must confirm first.
enum AuthRegisterResult: Equatable, Sendable {
    case signedIn(AuthUser)
    case confirmationRequired
}

/// Email account operations (Android `AuthRepository`). Every call except `logout`
/// fails fast with `.network` when offline. Cancellation is rethrown, never mapped.
protocol AuthRepository: Sendable {
    func register(email: String, password: String, name: String) async throws(CancellationError) -> Result<AuthRegisterResult, AppError>
    func login(email: String, password: String) async throws(CancellationError) -> Result<AuthUser, AppError>

    /// Always succeeds: the local sign-out never depends on the network.
    func logout() async -> Result<Void, AppError>
    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError>

    /// Password reset is a two-step code flow: the request emails an 8-digit code, the
    /// reset verifies it and sets the new password. Verifying the code creates a session,
    /// so a successful reset leaves the user signed in.
    func requestPasswordReset(email: String) async throws(CancellationError) -> Result<Void, AppError>
    func resetPassword(email: String, code: String, newPassword: String) async throws(CancellationError) -> Result<AuthUser, AppError>

    /// Permanently deletes the account on the server and clears local auth state.
    /// Lists live on the device, so they are untouched.
    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError>
}
