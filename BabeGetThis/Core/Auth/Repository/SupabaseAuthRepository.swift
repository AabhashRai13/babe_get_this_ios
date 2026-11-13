import Foundation

/// Port of Android's `SupabaseAuthRepository`: email sign-up/in, password reset, profile
/// name, sign-out and account deletion, persisting the session through `AuthStateManager`.
final class SupabaseAuthRepository: AuthRepository {
    private let remote: any AuthRemote
    private let authStateManager: AuthStateManager
    private let networkMonitor: NetworkMonitor

    init(remote: any AuthRemote, authStateManager: AuthStateManager, networkMonitor: NetworkMonitor) {
        self.remote = remote
        self.authStateManager = authStateManager
        self.networkMonitor = networkMonitor
    }

    func register(email: String, password: String, name: String) async throws(CancellationError) -> Result<AuthRegisterResult, AppError> {
        try await runCatchingAuth {
            // "Confirm email" OFF: sign-up creates a session at once. ON: no session yet.
            guard let session = try await remote.signUp(email: email, password: password, name: name) else {
                return .confirmationRequired
            }
            return .signedIn(persist(session, fallbackName: name, fallbackEmail: email))
        }
    }

    func login(email: String, password: String) async throws(CancellationError) -> Result<AuthUser, AppError> {
        try await runCatchingAuth {
            let session = try await remote.signIn(email: email, password: password)
            return persist(session, fallbackName: Self.localPart(of: email), fallbackEmail: email)
        }
    }

    func logout() async -> Result<Void, AppError> {
        // NOT wrapped in runCatchingAuth: its offline guard would abort logout and leave
        // the user stuck signed in. Logout must always succeed locally.
        //
        // Our own state first: clearing the Supabase session fires its signed-out event,
        // which the app mirrors as a LOST session, a no-op only once the user id is gone.
        // The other way round, every sign-out passed through "session expired".
        authStateManager.logout()
        await clearSupabaseSession()
        return .success(())
    }

    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError> {
        try await runCatchingAuth {
            let updated = try await remote.updateName(name)
            // Keep the locally cached name in sync for the profile screen.
            authStateManager.updateName(name)
            return Self.user(updated, fallbackName: name, fallbackEmail: authStateManager.currentEmail() ?? "")
        }
    }

    func requestPasswordReset(email: String) async throws(CancellationError) -> Result<Void, AppError> {
        try await runCatchingAuth {
            try await remote.requestPasswordReset(email: email)
        }
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws(CancellationError) -> Result<AuthUser, AppError> {
        try await runCatchingAuth {
            // Verifying the recovery code signs the user in, so the password update has a
            // session to work with and the user lands in the app authenticated.
            try await remote.verifyRecoveryCode(email: email, code: code)
            try await remote.updatePassword(newPassword)
            guard let session = remote.currentSession() else { throw AuthRepositoryFailure.noSession }
            return persist(session, fallbackName: Self.localPart(of: email), fallbackEmail: email)
        }
    }

    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError> {
        try await runCatchingAuth {
            guard remote.currentSession() != nil else { throw AuthRepositoryFailure.notSignedIn }
            try await remote.deleteUser()
            // The user row is gone, so the server can't cleanly end the session: clear
            // everything locally, in the same order as logout().
            authStateManager.logout()
            await clearSupabaseSession()
        }
    }

    // MARK: - Helpers

    /// A failed sign-out (offline) still clears the stored session, so it is ignored.
    private func clearSupabaseSession() async {
        try? await remote.signOut()
    }

    /// Copies the session into our own storage (which flips the state to authenticated)
    /// and returns the domain user.
    private func persist(_ session: AuthRemoteSession, fallbackName: String, fallbackEmail: String) -> AuthUser {
        let user = session.user
        let email = user.email ?? fallbackEmail
        // No name anywhere: use the email's local part rather than a blank name.
        let name = user.metadataName ?? (Self.isBlank(fallbackName) ? Self.localPart(of: email) : fallbackName)
        authStateManager.login(token: session.accessToken, userId: user.id, userName: name, userEmail: email)
        return AuthUser(id: user.id, email: email, name: name)
    }

    private static func user(_ user: AuthRemoteUser, fallbackName: String, fallbackEmail: String) -> AuthUser {
        AuthUser(id: user.id, email: user.email ?? fallbackEmail, name: user.metadataName ?? fallbackName)
    }

    /// Kotlin's `substringBefore("@")`: the whole string when there is no "@".
    private static func localPart(of email: String) -> String {
        String(email.prefix { $0 != "@" })
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// One place to turn auth failures into AppErrors. Supabase errors are mapped by
    /// message (`AuthErrorMapper`), not by `SafeCall`'s status mapping.
    private func runCatchingAuth<T>(_ block: () async throws -> T) async throws(CancellationError) -> Result<T, AppError> {
        // Fail fast offline with a clean message instead of a raw transport error.
        guard networkMonitor.isOnline() else { return .failure(.network()) }
        do {
            return .success(try await block())
        } catch is CancellationError {
            // A screen torn down mid-login simply stops; it is not "Authentication failed".
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timeout())
        } catch {
            // The connection can drop mid-request with the transport error wrapped
            // several causes deep: walk the chain before calling it bad credentials.
            if AuthErrorMapper.isNetworkFailure(error) { return .failure(.network()) }
            return .failure(.auth(AuthErrorMapper.friendlyMessage(for: error)))
        }
    }
}

/// Repository-side failures. Their text is never shown: the mapper turns them into
/// generic copy, as Android does for its `error(...)` calls.
enum AuthRepositoryFailure: Error, Equatable {
    case noSession
    case notSignedIn
}
