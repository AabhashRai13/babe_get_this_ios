import XCTest
@testable import BabeGetThis

// MARK: - Fakes

private let loginTestUser = AuthUser(id: "u1", email: "a@b.com", name: "Ann")

final class LoginTestAuthRepository: AuthRepository, LoginGoogleAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var _loginCalls: [(String, String)] = []
    private var _googleCalls: [(String, String)] = []
    var loginResult: Result<AuthUser, AppError> = .success(loginTestUser)
    var googleResult: Result<AuthUser, AppError> = .success(loginTestUser)

    var loginCalls: [(String, String)] { lock.withLock { _loginCalls } }
    var googleCalls: [(String, String)] { lock.withLock { _googleCalls } }

    func login(email: String, password: String) async throws(CancellationError) -> Result<AuthUser, AppError> {
        lock.withLock { _loginCalls.append((email, password)) }
        return loginResult
    }

    func signInWithGoogle(idToken: String, rawNonce: String) async -> Result<AuthUser, AppError> {
        lock.withLock { _googleCalls.append((idToken, rawNonce)) }
        return googleResult
    }

    func register(email: String, password: String, name: String) async throws(CancellationError) -> Result<AuthRegisterResult, AppError> { fatalError() }
    func logout() async -> Result<Void, AppError> { fatalError() }
    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError> { fatalError() }
    func requestPasswordReset(email: String) async throws(CancellationError) -> Result<Void, AppError> { fatalError() }
    func resetPassword(email: String, code: String, newPassword: String) async throws(CancellationError) -> Result<AuthUser, AppError> { fatalError() }
    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError> { fatalError() }
}

final class LoginTestTokenRequester: LoginGoogleTokenRequester, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests = 0
    private var waiter: CheckedContinuation<GoogleSignInToken?, Never>?
    /// A `complete(_:)` that arrived before `request()` installed its continuation.
    private var pending: GoogleSignInToken??
    var outcome: Result<GoogleSignInToken?, any Error> = .success(nil)
    /// When true, `request()` suspends until `complete(_:)`.
    var suspends = false

    var requests: Int { lock.withLock { _requests } }

    func request() async throws -> GoogleSignInToken? {
        if suspends {
            // The count, the pending check and the waiter are one critical section, so a test
            // that sees `requests == 1` and calls `complete` can't slip in between them.
            return await withCheckedContinuation { c in
                let early = lock.withLock { () -> GoogleSignInToken?? in
                    _requests += 1
                    if let early = pending {
                        pending = nil
                        return .some(early)
                    }
                    waiter = c
                    return nil
                }
                if let early { c.resume(returning: early) }
            }
        }
        lock.withLock { _requests += 1 }
        return try outcome.get()
    }

    /// Safe to call before `request()` suspends: the token is then handed over when it does.
    func complete(_ token: GoogleSignInToken?) {
        let c = lock.withLock { () -> CheckedContinuation<GoogleSignInToken?, Never>? in
            guard let c = waiter else {
                pending = .some(token)
                return nil
            }
            waiter = nil
            return c
        }
        c?.resume(returning: token)
    }
}

final class LoginTestReporter: AppErrorReporter, @unchecked Sendable {
    private let lock = NSLock()
    private var _reports: [(any Error, AppError)] = []
    var reports: [(any Error, AppError)] { lock.withLock { _reports } }
    func report(_ error: any Error, mapped: AppError) { lock.withLock { _reports.append((error, mapped)) } }
}

final class LoginTestAnalytics: LoginAnalytics, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    func trackAccountLoggedIn() { lock.withLock { _count += 1 } }
}

// MARK: - Tests (port of Android LoginViewModelTest)

@MainActor
final class LoginViewModelTests: XCTestCase {
    private var repo: LoginTestAuthRepository!
    private var tokens: LoginTestTokenRequester!
    private var reporter: LoginTestReporter!
    private var analytics: LoginTestAnalytics!
    private var successCount = 0
    private let token = GoogleSignInToken(idToken: "id-token", rawNonce: "raw-nonce")

    override func setUp() async throws {
        repo = LoginTestAuthRepository()
        tokens = LoginTestTokenRequester()
        reporter = LoginTestReporter()
        analytics = LoginTestAnalytics()
        successCount = 0
    }

    private func makeViewModel() -> LoginViewModel {
        let vm = LoginViewModel(authRepository: repo, googleAuth: repo, googleTokens: tokens,
                                analytics: analytics, reporter: reporter)
        vm.onLoginSuccess = { [unowned self] in successCount += 1 }
        return vm
    }

    private func fillValid(_ vm: LoginViewModel) {
        vm.onEmailChange("a@b.com")
        vm.onPasswordChange("secret1")
    }

    private func settle(_ vm: LoginViewModel) async {
        await vm.inFlight?.value
    }

    func testPristineFormIsInvalidAndShowsNoErrors() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.isFormValid)
        XCTAssertNil(vm.emailError)
    }

    func testBadEmailSetsInlineErrorAndKeepsFormInvalid() {
        let vm = makeViewModel()
        vm.onEmailChange("not-an-email")
        vm.onPasswordChange("secret1")
        XCTAssertNotNil(vm.emailError)
        XCTAssertFalse(vm.isFormValid)
    }

    func testValidEmailAndNonEmptyPasswordMakeFormValid() {
        let vm = makeViewModel()
        fillValid(vm)
        XCTAssertNil(vm.emailError)
        XCTAssertTrue(vm.isFormValid)
    }

    func testBlankPasswordKeepsFormInvalid() {
        let vm = makeViewModel()
        vm.onEmailChange("a@b.com")
        vm.onPasswordChange("   ")
        XCTAssertFalse(vm.isFormValid)
    }

    func testClearingEmailRemovesInlineError() {
        let vm = makeViewModel()
        vm.onEmailChange("nope")
        XCTAssertEqual(vm.emailError, "Enter a valid email address")
        vm.onEmailChange("")
        XCTAssertNil(vm.emailError)
    }

    func testLoginOnInvalidFormDoesNotCallRepository() async {
        let vm = makeViewModel()
        vm.onEmailChange("nope")
        vm.login()
        await settle(vm)
        XCTAssertTrue(repo.loginCalls.isEmpty)
        XCTAssertFalse(vm.isLoading)
    }

    func testSuccessfulLoginSignalsSuccessAndStopsLoading() async {
        let vm = makeViewModel()
        fillValid(vm)
        vm.login()
        XCTAssertTrue(vm.isLoading)
        await settle(vm)
        XCTAssertEqual(successCount, 1)
        XCTAssertEqual(repo.loginCalls.count, 1)
        XCTAssertEqual(repo.loginCalls.first?.0, "a@b.com")
        XCTAssertEqual(repo.loginCalls.first?.1, "secret1")
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(analytics.count, 1)
    }

    func testFailedLoginSurfacesErrorAndDoesNotSignalSuccess() async {
        repo.loginResult = .failure(.auth("Invalid email or password."))
        let vm = makeViewModel()
        fillValid(vm)
        vm.login()
        await settle(vm)
        XCTAssertEqual(successCount, 0)
        XCTAssertEqual(vm.errorMessage, "Invalid email or password.")
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(analytics.count, 0)
    }

    func testClearErrorWipesCurrentErrorMessage() async {
        repo.loginResult = .failure(.auth("Invalid email or password."))
        let vm = makeViewModel()
        fillValid(vm)
        vm.login()
        await settle(vm)
        XCTAssertEqual(vm.errorMessage, "Invalid email or password.")
        vm.clearError()
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: Google

    // Deliberately on a pristine form: Google sign-in must not depend on the fields.
    func testGoogleSignInForwardsTokenAndSignalsSuccess() async {
        tokens.outcome = .success(token)
        let vm = makeViewModel()
        vm.signInWithGoogle()
        await settle(vm)
        XCTAssertEqual(successCount, 1)
        XCTAssertEqual(repo.googleCalls.count, 1)
        XCTAssertEqual(repo.googleCalls.first?.0, "id-token")
        XCTAssertEqual(repo.googleCalls.first?.1, "raw-nonce")
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func testRejectedGoogleTokenSurfacesErrorAndDoesNotSignalSuccess() async {
        tokens.outcome = .success(token)
        repo.googleResult = .failure(.auth(AuthErrorMapper.googleSignInFailed))
        let vm = makeViewModel()
        vm.signInWithGoogle()
        await settle(vm)
        XCTAssertEqual(successCount, 0)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.errorMessage, AuthErrorMapper.googleSignInFailed)
    }

    // Closing the sheet is a choice, not a failure.
    func testClosingGoogleSheetIsSilent() async {
        tokens.outcome = .success(nil)
        let vm = makeViewModel()
        vm.signInWithGoogle()
        await settle(vm)
        XCTAssertEqual(successCount, 0)
        XCTAssertTrue(repo.googleCalls.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    // A failing sheet must reach crash reporting as `.unknown` (the type the policy transmits).
    func testFailingGoogleSheetIsShownAndReported() async {
        let failure = GoogleSheetFailure.failed("developer error")
        tokens.outcome = .failure(failure)
        let vm = makeViewModel()
        vm.signInWithGoogle()
        await settle(vm)
        XCTAssertEqual(vm.errorMessage, AuthErrorMapper.googleSignInFailed)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(reporter.reports.count, 1)
        XCTAssertEqual(reporter.reports.first?.0 as? GoogleSheetFailure, failure)
        XCTAssertEqual(reporter.reports.first?.1, .unknown(AuthErrorMapper.googleSignInFailed))
        XCTAssertTrue(repo.googleCalls.isEmpty)
    }

    func testUnparseableGoogleCredentialIsShownAndReported() async {
        let failure = GoogleSheetFailure.failed("bad bundle")
        tokens.outcome = .failure(failure)
        let vm = makeViewModel()
        vm.signInWithGoogle()
        await settle(vm)
        XCTAssertEqual(vm.errorMessage, AuthErrorMapper.googleSignInFailed)
        XCTAssertEqual(reporter.reports.first?.1, .unknown(AuthErrorMapper.googleSignInFailed))
    }

    // Offline: the standard offline message, nothing reported.
    func testGoogleSignInOfflineShowsNetworkMessage() async {
        tokens.outcome = .failure(GoogleSheetFailure.offline)
        let vm = makeViewModel()
        vm.signInWithGoogle()
        await settle(vm)
        XCTAssertEqual(vm.errorMessage, AppError.network().message)
        XCTAssertTrue(reporter.reports.isEmpty)
        XCTAssertTrue(repo.googleCalls.isEmpty)
    }

    func testNoGoogleAccountAsksUserToAddOne() async {
        tokens.outcome = .failure(GoogleSheetFailure.noAccount)
        let vm = makeViewModel()
        vm.signInWithGoogle()
        await settle(vm)
        XCTAssertEqual(vm.errorMessage, "Add a Google account to this device, then try again.")
        XCTAssertTrue(reporter.reports.isEmpty)
    }

    // A double tap must not open a second sheet while the first is still up.
    func testSecondGoogleTapWhileSheetOpenIsIgnored() async {
        tokens.suspends = true
        let vm = makeViewModel()
        vm.signInWithGoogle()
        vm.signInWithGoogle()
        // Let the first task reach the requester.
        while tokens.requests == 0 { await Task.yield() }
        XCTAssertEqual(tokens.requests, 1)
        XCTAssertTrue(vm.isLoading)
        tokens.complete(nil)
        await settle(vm)
        XCTAssertEqual(tokens.requests, 1)
        XCTAssertFalse(vm.isLoading)
    }

    func testEmailLoginIsIgnoredWhileGoogleSheetIsOpen() async {
        tokens.suspends = true
        let vm = makeViewModel()
        fillValid(vm)
        vm.signInWithGoogle()
        vm.login()
        while tokens.requests == 0 { await Task.yield() }
        tokens.complete(nil)
        await settle(vm)
        XCTAssertTrue(repo.loginCalls.isEmpty)
    }

    func testEmailValidatorMatchesAndroidRegex() {
        XCTAssertTrue(LoginEmailValidator.isValid("a@b.co"))
        XCTAssertFalse(LoginEmailValidator.isValid("a@b"))
        XCTAssertFalse(LoginEmailValidator.isValid("a b@c.com"))
        XCTAssertFalse(LoginEmailValidator.isValid("a@@b.com"))
    }

    // Three paths share one guard, but the spinner shows only on the button that was pressed:
    // a Google or Apple attempt must not turn "Sign in" into a spinner.
    func testOnlyTheRunningPathShowsASpinnerAndEveryButtonIsDisabled() async {
        let sources: [LoginViewModel.SignInSource] = [.email, .google, .apple]
        let vm = makeViewModel()
        fillValid(vm)
        XCTAssertTrue(vm.isEmailSignInEnabled)
        XCTAssertFalse(sources.contains { vm.showsSpinner(for: $0) })

        tokens.suspends = true
        vm.signInWithGoogle()
        XCTAssertEqual(vm.inFlightSource, .google)
        XCTAssertEqual(sources.filter { vm.showsSpinner(for: $0) }, [.google])
        XCTAssertTrue(vm.isLoading, "Google and Apple are disabled")
        XCTAssertFalse(vm.isEmailSignInEnabled, "Sign in is disabled but shows no spinner")
        tokens.complete(nil)
        await settle(vm)
        XCTAssertNil(vm.inFlightSource)
        XCTAssertTrue(vm.isEmailSignInEnabled)

        vm.login()
        XCTAssertEqual(sources.filter { vm.showsSpinner(for: $0) }, [.email])
        await settle(vm)

        _ = vm.prepareAppleSignIn()
        vm.completeAppleSignIn(.authorized(identityToken: Data("apple-id-token".utf8), fullName: nil))
        XCTAssertEqual(sources.filter { vm.showsSpinner(for: $0) }, [.apple])
        XCTAssertFalse(vm.isEmailSignInEnabled)
        await settle(vm)
        XCTAssertNil(vm.inFlightSource)
        XCTAssertFalse(vm.isLoading)
    }
}
