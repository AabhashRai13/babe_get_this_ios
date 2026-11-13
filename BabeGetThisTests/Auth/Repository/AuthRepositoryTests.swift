import Foundation
import XCTest
@testable import BabeGetThis

/// SupabaseAuthRepository against a fake remote (parity AUTH-07, AUTH-08, AUTH-09, SESS-05).
/// Android has no test class for the repository itself; these pin its behaviour.
final class AuthRepositoryTests: XCTestCase {
    private var remote: AuthRepositoryFakeRemote!
    private var path: AuthRepositoryFakePathSource!
    private var tokens: InMemoryTokenStore!
    private var authState: AuthStateManager!
    private var repository: SupabaseAuthRepository!

    override func setUp() {
        super.setUp()
        remote = AuthRepositoryFakeRemote()
        path = AuthRepositoryFakePathSource()
        tokens = InMemoryTokenStore()
        authState = AuthStateManager(tokenStore: tokens)
        authState.initialize()
        repository = SupabaseAuthRepository(
            remote: remote, authStateManager: authState, networkMonitor: NetworkMonitor(source: path)
        )
    }

    private func signIn() {
        authState.login(token: "access-0", userId: "user-1", userName: "Ann", userEmail: "ann@example.com")
        remote.storedSession = AuthRepositoryFakeRemote.session(token: "access-0")
    }

    // MARK: - Offline guard (AUTH-08, SESS-05)

    func testEveryCallButLogoutFailsFastOffline() async throws {
        signIn()
        path.isOnline = false

        let register = try await repository.register(email: "a@b.c", password: "secret1", name: "A")
        let login = try await repository.login(email: "a@b.c", password: "secret1")
        let rename = try await repository.updateUserName("New")
        let requestReset = try await repository.requestPasswordReset(email: "a@b.c")
        let reset = try await repository.resetPassword(email: "a@b.c", code: "12345678", newPassword: "secret2")
        let delete = try await repository.deleteAccount()

        XCTAssertEqual(register.failure, .network())
        XCTAssertEqual(login.failure, .network())
        XCTAssertEqual(rename.failure, .network())
        XCTAssertEqual(requestReset.failure, .network())
        XCTAssertEqual(reset.failure, .network())
        XCTAssertEqual(delete.failure, .network())
        XCTAssertEqual(remote.calls, [], "nothing may reach Supabase while offline")
        XCTAssertEqual(authState.authState, .authenticated(userId: "user-1"))

        let logout = await repository.logout()

        XCTAssertNoThrow(try logout.get())
        XCTAssertEqual(remote.calls, ["signOut"])
        XCTAssertEqual(authState.authState, .unauthenticated)
    }

    // MARK: - Logout (SESS-05)

    // Our state is cleared before Supabase's, so its signed-out event finds no user id
    // and can't turn the sign-out into "session expired".
    func testLogoutClearsLocalStateBeforeTheSupabaseSession() async {
        signIn()
        let stateAtSignOut = LockedAuthStates()
        remote.onSignOut = { [authState] in stateAtSignOut.append(authState!.authState) }

        _ = await repository.logout()

        XCTAssertEqual(stateAtSignOut.values, [.unauthenticated])
        XCTAssertNil(tokens.userId())
        XCTAssertNil(tokens.token())
    }

    func testLogoutSucceedsEvenWhenTheSupabaseSignOutFails() async {
        signIn()
        remote.signOutError = URLError(.notConnectedToInternet)

        let result = await repository.logout()

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(authState.authState, .unauthenticated)
        XCTAssertNil(authState.userName)
    }

    // MARK: - Register

    func testRegisterWithASessionSignsInAndPersists() async throws {
        remote.signUpResult = .success(AuthRepositoryFakeRemote.session(
            token: "access-9", user: AuthRepositoryFakeRemote.user(id: "user-9", email: "bo@example.com", name: "Bo")
        ))

        let result = try await repository.register(email: "bo@example.com", password: "secret1", name: "Bo")

        let expected = AuthUser(id: "user-9", email: "bo@example.com", name: "Bo")
        XCTAssertEqual(try result.get(), .signedIn(expected))
        XCTAssertEqual(remote.calls.first, "signUp(bo@example.com,Bo)")
        XCTAssertEqual(authState.authState, .authenticated(userId: "user-9"))
        XCTAssertEqual(tokens.token(), "access-9")
        XCTAssertEqual(tokens.userName(), "Bo")
        XCTAssertEqual(tokens.userEmail(), "bo@example.com")
    }

    func testRegisterWithoutASessionNeedsConfirmationAndStaysSignedOut() async throws {
        remote.signUpResult = .success(nil)

        let result = try await repository.register(email: "bo@example.com", password: "secret1", name: "Bo")

        XCTAssertEqual(try result.get(), .confirmationRequired)
        XCTAssertEqual(authState.authState, .unauthenticated)
        XCTAssertNil(tokens.token())
    }

    func testATakenEmailOnRegisterGetsFriendlyCopy() async throws {
        remote.failure = AuthRepositoryProviderFailure(message: "User already registered")

        let result = try await repository.register(email: "bo@example.com", password: "secret1", name: "Bo")

        XCTAssertEqual(result.failure, .auth("That email is already registered."))
    }

    // MARK: - Display name (AUTH-09)

    func testRegisterUsesTheTypedNameWhenTheUserHasNoMetadataName() async throws {
        remote.signUpResult = .success(AuthRepositoryFakeRemote.session(user: AuthRepositoryFakeRemote.user(name: nil)))

        let user = try await repository.register(email: "ann@example.com", password: "secret1", name: "Annie").get()

        XCTAssertEqual(user, .signedIn(AuthUser(id: "user-1", email: "ann@example.com", name: "Annie")))
    }

    func testABlankFallbackNameBecomesTheEmailLocalPart() async throws {
        remote.signUpResult = .success(AuthRepositoryFakeRemote.session(user: AuthRepositoryFakeRemote.user(name: nil)))

        let user = try await repository.register(email: "ann@example.com", password: "secret1", name: "   ").get()

        XCTAssertEqual(user, .signedIn(AuthUser(id: "user-1", email: "ann@example.com", name: "ann")))
    }

    func testLoginPrefersTheMetadataName() async throws {
        remote.signInResult = .success(AuthRepositoryFakeRemote.session(user: AuthRepositoryFakeRemote.user(name: "Ann Lee")))

        let user = try await repository.login(email: "ann@example.com", password: "secret1").get()

        XCTAssertEqual(user, AuthUser(id: "user-1", email: "ann@example.com", name: "Ann Lee"))
        XCTAssertEqual(authState.userName, "Ann Lee")
    }

    func testLoginFallsBackToTheEmailLocalPartAndTheTypedEmail() async throws {
        remote.signInResult = .success(AuthRepositoryFakeRemote.session(user: AuthRepositoryFakeRemote.user(email: nil, name: nil)))

        let user = try await repository.login(email: "ann@example.com", password: "secret1").get()

        XCTAssertEqual(user, AuthUser(id: "user-1", email: "ann@example.com", name: "ann"))
        XCTAssertEqual(authState.authState, .authenticated(userId: "user-1"))
        XCTAssertEqual(tokens.userEmail(), "ann@example.com")
    }

    // MARK: - Error mapping (AUTH-07)

    func testBadCredentialsMapToFriendlyAuthCopy() async throws {
        remote.failure = AuthRepositoryProviderFailure(message: "Invalid login credentials")

        let result = try await repository.login(email: "ann@example.com", password: "wrong")

        XCTAssertEqual(result.failure, .auth("Invalid email or password."))
        XCTAssertEqual(authState.authState, .unauthenticated)
    }

    func testATransportErrorWrappedMidRequestIsNetworkNotBadCredentials() async throws {
        remote.failure = NSError(domain: "SupabaseWrapper", code: 1, userInfo: [
            NSUnderlyingErrorKey: URLError(.networkConnectionLost),
        ])

        let result = try await repository.login(email: "ann@example.com", password: "secret1")

        XCTAssertEqual(result.failure, .network())
    }

    func testATimeoutIsATimeout() async throws {
        remote.failure = URLError(.timedOut)

        let result = try await repository.login(email: "ann@example.com", password: "secret1")

        XCTAssertEqual(result.failure, .timeout())
    }

    func testCancellationIsRethrownNotMapped() async {
        remote.failure = CancellationError()

        do {
            _ = try await repository.login(email: "ann@example.com", password: "secret1")
            XCTFail("expected cancellation to be rethrown")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    // MARK: - Profile name

    func testUpdateUserNameUpdatesTheCachedName() async throws {
        signIn()
        remote.updateNameResult = .success(AuthRepositoryFakeRemote.user(email: nil, name: "Annie"))

        let user = try await repository.updateUserName("Annie").get()

        XCTAssertEqual(user, AuthUser(id: "user-1", email: "ann@example.com", name: "Annie"))
        XCTAssertEqual(remote.calls, ["updateName(Annie)"])
        XCTAssertEqual(authState.userName, "Annie")
        XCTAssertEqual(tokens.userName(), "Annie")
    }

    // MARK: - Password reset

    func testRequestPasswordResetEmailsACode() async throws {
        let result = try await repository.requestPasswordReset(email: "ann@example.com")

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(remote.calls, ["requestPasswordReset(ann@example.com)"])
    }

    func testResetPasswordVerifiesTheCodeThenSetsThePasswordAndSignsIn() async throws {
        remote.storedSession = AuthRepositoryFakeRemote.session(token: "access-r", user: AuthRepositoryFakeRemote.user(name: nil))

        let user = try await repository.resetPassword(email: "ann@example.com", code: "12345678", newPassword: "secret2").get()

        XCTAssertEqual(remote.calls, [
            "verifyRecoveryCode(ann@example.com,12345678)", "updatePassword(secret2)", "currentSession",
        ])
        XCTAssertEqual(user, AuthUser(id: "user-1", email: "ann@example.com", name: "ann"))
        XCTAssertEqual(authState.authState, .authenticated(userId: "user-1"))
        XCTAssertEqual(tokens.token(), "access-r")
    }

    func testAWrongResetCodeIsExplained() async throws {
        remote.failure = AuthRepositoryProviderFailure(message: "Token has expired or is invalid")

        let result = try await repository.resetPassword(email: "ann@example.com", code: "00000000", newPassword: "secret2")

        XCTAssertEqual(result.failure, .auth("That code has expired. Request a new one."))
        XCTAssertEqual(authState.authState, .unauthenticated)
    }

    // MARK: - Delete account

    func testDeleteAccountCallsDeleteUserThenClearsEverythingLocally() async throws {
        signIn()

        let result = try await repository.deleteAccount()

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(remote.calls, ["currentSession", "deleteUser", "signOut"])
        XCTAssertEqual(authState.authState, .unauthenticated)
        XCTAssertNil(tokens.userId())
    }

    func testDeleteAccountWithoutASessionFailsWithoutCallingTheServer() async throws {
        let result = try await repository.deleteAccount()

        XCTAssertEqual(result.failure, .auth("Authentication failed. Please try again."))
        XCTAssertEqual(remote.calls, ["currentSession"])
    }

    func testAFailedDeleteKeepsTheUserSignedIn() async throws {
        signIn()
        remote.deleteUserError = AuthRepositoryProviderFailure(message: "permission denied for function delete_user")

        let result = try await repository.deleteAccount()

        XCTAssertEqual(result.failure, .auth("Authentication failed. Please try again."))
        XCTAssertEqual(authState.authState, .authenticated(userId: "user-1"))
        XCTAssertFalse(remote.calls.contains("signOut"))
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}

private final class LockedAuthStates: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [AuthState] = []

    var values: [AuthState] { lock.withLock { stored } }

    func append(_ state: AuthState) {
        lock.withLock { stored.append(state) }
    }
}
