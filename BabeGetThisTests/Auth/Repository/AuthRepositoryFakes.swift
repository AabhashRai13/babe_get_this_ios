import Foundation
@testable import BabeGetThis

/// Records every call and answers with the configured results. `onSignOut` runs inside
/// `signOut`, so a test can look at the app's state at that moment.
final class AuthRepositoryFakeRemote: AuthRemote, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var signUpResult: Result<AuthRemoteSession?, any Error> = .success(nil)
    var signInResult: Result<AuthRemoteSession, any Error> = .success(AuthRepositoryFakeRemote.session())
    var storedSession: AuthRemoteSession?
    var updateNameResult: Result<AuthRemoteUser, any Error> = .success(AuthRepositoryFakeRemote.user())
    var failure: (any Error)?
    var deleteUserError: (any Error)?
    var signOutError: (any Error)?
    var onSignOut: (() -> Void)?

    var calls: [String] { lock.withLock { recorded } }

    static func user(id: String = "user-1", email: String? = "ann@example.com", name: String? = nil) -> AuthRemoteUser {
        AuthRemoteUser(id: id, email: email, metadataName: name)
    }

    static func session(token: String = "access-1", user: AuthRemoteUser = user()) -> AuthRemoteSession {
        AuthRemoteSession(accessToken: token, user: user)
    }

    private func record(_ call: String) throws {
        lock.withLock { recorded.append(call) }
        if let failure { throw failure }
    }

    func signUp(email: String, password: String, name: String) async throws -> AuthRemoteSession? {
        try record("signUp(\(email),\(name))")
        let session = try signUpResult.get()
        if let session { storedSession = session }
        return session
    }

    func signIn(email: String, password: String) async throws -> AuthRemoteSession {
        try record("signIn(\(email))")
        let session = try signInResult.get()
        storedSession = session
        return session
    }

    func currentSession() -> AuthRemoteSession? {
        lock.withLock { recorded.append("currentSession") }
        return storedSession
    }

    func updateName(_ name: String) async throws -> AuthRemoteUser {
        try record("updateName(\(name))")
        return try updateNameResult.get()
    }

    func requestPasswordReset(email: String) async throws {
        try record("requestPasswordReset(\(email))")
    }

    func verifyRecoveryCode(email: String, code: String) async throws {
        try record("verifyRecoveryCode(\(email),\(code))")
    }

    func updatePassword(_ password: String) async throws {
        try record("updatePassword(\(password))")
    }

    func deleteUser() async throws {
        try record("deleteUser")
        if let deleteUserError { throw deleteUserError }
    }

    func signOut() async throws {
        lock.withLock { recorded.append("signOut") }
        onSignOut?()
        storedSession = nil
        if let signOutError { throw signOutError }
    }
}

final class AuthRepositoryFakePathSource: NetworkPathSource, @unchecked Sendable {
    private let lock = NSLock()
    private var path: NetworkPathSnapshot? = NetworkPathSnapshot(status: .satisfied)

    var isOnline: Bool {
        get { lock.withLock { path?.status == .satisfied } }
        set { lock.withLock { path = NetworkPathSnapshot(status: newValue ? .satisfied : .unsatisfied) } }
    }

    var currentPath: NetworkPathSnapshot? { lock.withLock { path } }
}

/// An error with a provider message, like a Supabase API error.
struct AuthRepositoryProviderFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
