import XCTest
@testable import BabeGetThis

private final class RegisterTestAuthRepository: AuthRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(String, String, String)] = []
    var result: Result<AuthRegisterResult, AppError> = .success(.confirmationRequired)

    var calls: [(String, String, String)] { lock.withLock { _calls } }

    func register(email: String, password: String, name: String) async throws(CancellationError) -> Result<AuthRegisterResult, AppError> {
        lock.withLock { _calls.append((email, password, name)) }
        return result
    }

    func login(email: String, password: String) async throws(CancellationError) -> Result<AuthUser, AppError> { fatalError() }
    func logout() async -> Result<Void, AppError> { fatalError() }
    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError> { fatalError() }
    func requestPasswordReset(email: String) async throws(CancellationError) -> Result<Void, AppError> { fatalError() }
    func resetPassword(email: String, code: String, newPassword: String) async throws(CancellationError) -> Result<AuthUser, AppError> { fatalError() }
    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError> { fatalError() }
}

private final class RegisterTestAnalytics: RegisterAnalytics, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    func trackAccountRegistered() { lock.withLock { _count += 1 } }
}

@MainActor
final class RegisterViewModelTests: XCTestCase {
    private let user = AuthUser(id: "u1", email: "a@b.com", name: "Ann")
    private var repo: RegisterTestAuthRepository!
    private var analytics: RegisterTestAnalytics!

    override func setUp() {
        repo = RegisterTestAuthRepository()
        analytics = RegisterTestAnalytics()
    }

    private func makeViewModel() -> RegisterViewModel {
        RegisterViewModel(authRepository: repo, analytics: analytics)
    }

    private func fillValid(_ vm: RegisterViewModel) {
        vm.onNameChange("Ann")
        vm.onEmailChange("a@b.com")
        vm.onPasswordChange("secret1")
        vm.onConfirmPasswordChange("secret1")
    }

    // MARK: Client-side validation (must not hit the repository)

    func testPristineFormIsInvalidAndRegisterDoesNotHitTheRepository() async {
        let vm = makeViewModel()
        XCTAssertFalse(vm.isFormValid)
        vm.register()
        await vm.inFlight?.value
        XCTAssertEqual(repo.calls.count, 0)
    }

    func testMismatchedPasswordsSetAConfirmErrorAndKeepTheFormInvalid() async {
        let vm = makeViewModel()
        vm.onNameChange("Ann")
        vm.onEmailChange("a@b.com")
        vm.onPasswordChange("secret1")
        vm.onConfirmPasswordChange("secret2")

        XCTAssertNotNil(vm.confirmPasswordError)
        XCTAssertFalse(vm.isFormValid)
        vm.register()
        await vm.inFlight?.value
        XCTAssertEqual(repo.calls.count, 0)
    }

    func testTooShortPasswordSetsAPasswordErrorAndKeepsTheFormInvalid() async {
        let vm = makeViewModel()
        vm.onNameChange("Ann")
        vm.onEmailChange("a@b.com")
        vm.onPasswordChange("123")
        vm.onConfirmPasswordChange("123")

        XCTAssertNotNil(vm.passwordError)
        XCTAssertFalse(vm.isFormValid)
        vm.register()
        await vm.inFlight?.value
        XCTAssertEqual(repo.calls.count, 0)
    }

    func testBadEmailSetsAnEmailErrorAndKeepsTheFormInvalid() {
        let vm = makeViewModel()
        vm.onEmailChange("not-an-email")
        XCTAssertNotNil(vm.emailError)
        XCTAssertFalse(vm.isFormValid)
    }

    func testFullyValidFormClearsErrorsAndIsValid() {
        let vm = makeViewModel()
        fillValid(vm)
        XCTAssertNil(vm.emailError)
        XCTAssertNil(vm.passwordError)
        XCTAssertNil(vm.confirmPasswordError)
        XCTAssertTrue(vm.isFormValid)
    }

    // MARK: RegisterResult branching

    func testSignedInResultSignalsSuccessTracksAndStopsLoading() async {
        repo.result = .success(.signedIn(user))
        let vm = makeViewModel()
        var successes = 0
        vm.onRegisterSuccess = { successes += 1 }
        fillValid(vm)

        vm.register()
        await vm.inFlight?.value

        XCTAssertEqual(successes, 1)
        XCTAssertEqual(analytics.count, 1)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(repo.calls.first?.0, "a@b.com")
        XCTAssertEqual(repo.calls.first?.2, "Ann")
    }

    func testConfirmationRequiredShowsTheConfirmMessageAndDoesNotSignalSuccess() async {
        repo.result = .success(.confirmationRequired)
        let vm = makeViewModel()
        var successes = 0
        vm.onRegisterSuccess = { successes += 1 }
        fillValid(vm)

        vm.register()
        await vm.inFlight?.value

        XCTAssertEqual(successes, 0)
        XCTAssertEqual(analytics.count, 0)
        XCTAssertEqual(vm.errorMessage, "Check your email to confirm your account, then sign in.")
        XCTAssertFalse(vm.isLoading)
    }

    func testRepositoryErrorSurfacesTheErrorMessage() async {
        repo.result = .failure(.auth("That email is already registered."))
        let vm = makeViewModel()
        fillValid(vm)

        vm.register()
        await vm.inFlight?.value

        XCTAssertEqual(vm.errorMessage, "That email is already registered.")
        XCTAssertFalse(vm.isLoading)
    }

    func testClearErrorWipesTheCurrentErrorMessage() async {
        repo.result = .failure(.auth("That email is already registered."))
        let vm = makeViewModel()
        fillValid(vm)
        vm.register()
        await vm.inFlight?.value
        XCTAssertEqual(vm.errorMessage, "That email is already registered.")

        vm.clearError()

        XCTAssertNil(vm.errorMessage)
    }
}
