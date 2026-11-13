import Foundation
import Supabase

/// What the repository needs from a Supabase user.
struct AuthRemoteUser: Equatable, Sendable {
    let id: String
    let email: String?
    /// `user_metadata.name`, the display name, when set.
    let metadataName: String?
}

struct AuthRemoteSession: Equatable, Sendable {
    let accessToken: String
    let user: AuthRemoteUser
}

/// The Supabase Auth calls the repository makes, behind a seam so its logic is tested
/// with a fake. Errors are whatever supabase-swift throws; the repository maps them.
protocol AuthRemote: Sendable {
    /// The new session, or nil when the project requires email confirmation first.
    func signUp(email: String, password: String, name: String) async throws -> AuthRemoteSession?
    func signIn(email: String, password: String) async throws -> AuthRemoteSession
    /// The locally stored session, if any. No network.
    func currentSession() -> AuthRemoteSession?
    func updateName(_ name: String) async throws -> AuthRemoteUser
    func requestPasswordReset(email: String) async throws
    /// Verifies the emailed recovery code, which signs the user in.
    func verifyRecoveryCode(email: String, code: String) async throws
    func updatePassword(_ password: String) async throws
    /// Calls the `delete_user()` RPC, which deletes `auth.uid()`'s row.
    func deleteUser() async throws
    func signOut() async throws
}

/// `AuthRemote` over supabase-swift.
final class SupabaseAuthRemote: AuthRemote {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func signUp(email: String, password: String, name: String) async throws -> AuthRemoteSession? {
        // The display name goes into user_metadata so it lives on the Supabase user
        // record, not just locally.
        let response = try await client.auth.signUp(email: email, password: password, data: ["name": .string(name)])
        return response.session.map(Self.session)
    }

    func signIn(email: String, password: String) async throws -> AuthRemoteSession {
        Self.session(try await client.auth.signIn(email: email, password: password))
    }

    func currentSession() -> AuthRemoteSession? {
        client.auth.currentSession.map(Self.session)
    }

    func updateName(_ name: String) async throws -> AuthRemoteUser {
        Self.user(try await client.auth.update(user: UserAttributes(data: ["name": .string(name)])))
    }

    func requestPasswordReset(email: String) async throws {
        // Succeeds even for unknown emails, so it can't leak who is registered.
        try await client.auth.resetPasswordForEmail(email)
    }

    func verifyRecoveryCode(email: String, code: String) async throws {
        try await client.auth.verifyOTP(email: email, token: code, type: .recovery)
    }

    func updatePassword(_ password: String) async throws {
        try await client.auth.update(user: UserAttributes(password: password))
    }

    func deleteUser() async throws {
        // The anon key can't touch auth.users, so a security-definer function does it.
        try await client.rpc("delete_user").execute()
    }

    /// supabase-swift removes the stored session before it posts /logout, so even a
    /// failed (offline) sign-out leaves no session behind to be restored on next launch.
    func signOut() async throws {
        try await client.auth.signOut()
    }

    private static func session(_ session: Session) -> AuthRemoteSession {
        AuthRemoteSession(accessToken: session.accessToken, user: user(session.user))
    }

    /// Supabase ids are lowercase UUID strings everywhere else (`created_by`, RLS).
    private static func user(_ user: User) -> AuthRemoteUser {
        AuthRemoteUser(
            id: user.id.uuidString.lowercased(),
            email: user.email,
            metadataName: user.userMetadata["name"]?.stringValue
        )
    }
}
