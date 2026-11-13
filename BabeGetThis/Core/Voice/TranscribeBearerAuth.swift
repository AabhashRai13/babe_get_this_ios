import Foundation

/// Bearer token and 401 handling for our own API (Android `AuthInterceptor` + `AuthAuthenticator`).
///
/// `authorize` attaches the saved token to a request; with no token the request goes out
/// without the header. `handle` is consulted with each response: a 401 on a request that
/// carried a bearer expires the session (drop the token, keep the account, so its lists stay
/// on screen; Android decision 008). Nothing is retried and nothing is refreshed: Supabase
/// rotates the token in the background (`SessionObserver`).
struct TranscribeBearerAuth: Sendable {
    private let currentToken: @Sendable () -> String?
    private let expireSession: @Sendable () -> Void

    init(currentToken: @escaping @Sendable () -> String?, expireSession: @escaping @Sendable () -> Void) {
        self.currentToken = currentToken
        self.expireSession = expireSession
    }

    init(tokenStore: any TokenStore, authStateManager: AuthStateManager) {
        self.init(
            currentToken: { tokenStore.token() },
            expireSession: { authStateManager.expireSession() }
        )
    }

    /// Replaces (never appends) any Authorization the caller set; the rest of the request is untouched.
    func authorize(_ request: URLRequest) -> URLRequest {
        guard let token = currentToken() else { return request }
        var signed = request
        signed.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return signed
    }

    /// Without a bearer on the request there is no session to expire, so a 401 changes nothing.
    func handle(_ response: HTTPURLResponse, to request: URLRequest) {
        guard response.statusCode == 401, request.value(forHTTPHeaderField: "Authorization") != nil else { return }
        expireSession()
    }
}
