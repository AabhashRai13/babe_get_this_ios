import Foundation
@testable import BabeGetThis

/// One configurable `AuthRepository` for the AuthScreensTest port (Android mocks it with MockK).
/// Records every call; never touches the network.
final class ScreensAuthRepository: AuthRepository, LoginGoogleAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var _loginCalls: [(email: String, password: String)] = []
    private var _registerCalls: [(email: String, password: String, name: String)] = []
    private var _resetRequests: [String] = []

    var loginResult: Result<AuthUser, AppError> = .success(ScreensAuthRepository.user)
    var registerResult: Result<AuthRegisterResult, AppError> = .success(.signedIn(ScreensAuthRepository.user))
    var resetRequestResult: Result<Void, AppError> = .success(())

    static let user = AuthUser(id: "u1", email: "a@b.c", name: "Aabhash")

    var loginCalls: [(email: String, password: String)] { lock.withLock { _loginCalls } }
    var registerCalls: [(email: String, password: String, name: String)] { lock.withLock { _registerCalls } }
    var resetRequests: [String] { lock.withLock { _resetRequests } }

    func login(email: String, password: String) async throws(CancellationError) -> Result<AuthUser, AppError> {
        lock.withLock { _loginCalls.append((email, password)) }
        return loginResult
    }

    func register(email: String, password: String, name: String) async throws(CancellationError) -> Result<AuthRegisterResult, AppError> {
        lock.withLock { _registerCalls.append((email, password, name)) }
        return registerResult
    }

    func requestPasswordReset(email: String) async throws(CancellationError) -> Result<Void, AppError> {
        lock.withLock { _resetRequests.append(email) }
        return resetRequestResult
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws(CancellationError) -> Result<AuthUser, AppError> {
        .success(Self.user)
    }

    func signInWithGoogle(idToken: String, rawNonce: String) async -> Result<AuthUser, AppError> {
        .success(Self.user)
    }

    func logout() async -> Result<Void, AppError> { .success(()) }
    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError> { .success(Self.user) }
    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError> { .success(()) }
}

/// The Google sheet, closed without picking an account.
struct ScreensClosedGoogleSheet: LoginGoogleTokenRequester {
    func request() async throws -> GoogleSignInToken? { nil }
}

/// The Google sheet, counting how often it was asked; closed without picking an account.
final class ScreensCountingGoogleSheet: LoginGoogleTokenRequester, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests = 0
    var requests: Int { lock.withLock { _requests } }

    func request() async throws -> GoogleSignInToken? {
        lock.withLock { _requests += 1 }
        return nil
    }
}

/// The routes a screen's buttons asked for, in order.
@MainActor
final class ScreensRouteLog {
    private(set) var taken: [String] = []
    func record(_ route: String) { taken.append(route) }
}
