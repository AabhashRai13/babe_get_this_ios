import Foundation

/// The Apple half of the auth repository (AUTH-06), the same seam as `LoginGoogleAuthenticating`.
/// `fullName` is set only on the first authorisation and becomes `user_metadata.name`.
protocol LoginAppleAuthenticating: Sendable {
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async -> Result<AuthUser, AppError>
}

/// For view models built without Apple sign-in (previews, older tests): it always fails.
struct AppleSignInUnavailable: LoginAppleAuthenticating {
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async -> Result<AuthUser, AppError> {
        .failure(.auth(AuthErrorMapper.appleSignInFailed))
    }
}
