import XCTest
@testable import BabeGetThis

private final class ForgotTestAuthRepository: AuthRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _requestCalls: [String] = []
    private var _resetCalls: [(String, String, String)] = []
    var requestResult: Result<Void, AppError> = .success(())
    var resetResult: Result<AuthUser, AppError> = .success(AuthUser(id: "u1", email: "a@b.com", name: "Ann"))

    var requestCalls: [String] { lock.withLock { _requestCalls } }
    var resetCalls: [(String, String, String)] { lock.withLock { _resetCalls } }

    func requestPasswordReset(email: String) async throws(CancellationError) -> Result<Void, AppError> {
        lock.withLock { _requestCalls.append(email) }
        return requestResult
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws(CancellationError) -> Result<AuthUser, AppError> {
        lock.withLock { _resetCalls.append((email, code, newPassword)) }
        return resetResult
    }

    func register(email: String, password: String, name: String) async throws(CancellationError) -> Result<AuthRegisterResult, AppError> { fatalError() }
    func login(email: String, password: String) async throws(CancellationError) -> Result<AuthUser, AppError> { fatalError() }
    func logout() async -> Result<Void, AppError> { fatalError() }
    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError> { fatalError() }
    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError> { fatalError() }
}

@MainActor
final class ForgotPasswordViewModelTests: XCTestCase {
    private var repo: ForgotTestAuthRepository!

    override func setUp() {
        repo = ForgotTestAuthRepository()
    }

    private func makeViewModel() -> ForgotPasswordViewModel {
        ForgotPasswordViewModel(authRepository: repo)
    }

    func testSendCodeWithAnInvalidEmailDoesNotCallTheRepository() async {
        let vm = makeViewModel()
        vm.onEmailChange("not-an-email")
        vm.sendCode()
        await vm.inFlight?.value
        XCTAssertEqual(repo.requestCalls.count, 0)
    }

    func testSuccessfulSendCodeAdvancesToTheCodeStep() async {
        let vm = makeViewModel()
        vm.onEmailChange("a@b.com")
        vm.sendCode()
        await vm.inFlight?.value

        XCTAssertTrue(vm.codeSent)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(repo.requestCalls, ["a@b.com"])
    }

    func testFailedSendCodeSurfacesTheErrorAndStaysOnTheEmailStep() async {
        repo.requestResult = .failure(.network())
        let vm = makeViewModel()
        vm.onEmailChange("a@b.com")
        vm.sendCode()
        await vm.inFlight?.value

        XCTAssertFalse(vm.codeSent)
        XCTAssertEqual(vm.errorMessage, AppError.network().message)
    }

    func testCodeInputKeepsOnlyDigitsAndCapsAtEight() {
        let vm = makeViewModel()
        vm.onCodeChange("12a3-4567 89 01")
        XCTAssertEqual(vm.code, "12345678")
    }

    func testResetFormNeedsAFullCodeAndALongEnoughPassword() {
        let vm = makeViewModel()

        vm.onCodeChange("1234567")
        vm.onNewPasswordChange("secret1")
        XCTAssertFalse(vm.isResetFormValid)

        vm.onCodeChange("12345678")
        vm.onNewPasswordChange("short")
        XCTAssertFalse(vm.isResetFormValid)

        vm.onNewPasswordChange("secret1")
        XCTAssertTrue(vm.isResetFormValid)
    }

    func testSuccessfulResetSignalsSuccess() async {
        let vm = makeViewModel()
        var successes = 0
        vm.onResetSuccess = { successes += 1 }
        vm.onEmailChange("a@b.com")
        vm.onCodeChange("12345678")
        vm.onNewPasswordChange("secret1")

        vm.resetPassword()
        await vm.inFlight?.value

        XCTAssertEqual(successes, 1)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(repo.resetCalls.first?.1, "12345678")
    }

    func testFailedResetSurfacesTheErrorAndDoesNotSignalSuccess() async {
        repo.resetResult = .failure(.auth("Invalid code. Check the email and try again."))
        let vm = makeViewModel()
        var successes = 0
        vm.onResetSuccess = { successes += 1 }
        vm.onEmailChange("a@b.com")
        vm.onCodeChange("12345678")
        vm.onNewPasswordChange("secret1")

        vm.resetPassword()
        await vm.inFlight?.value

        XCTAssertEqual(successes, 0)
        XCTAssertEqual(vm.errorMessage, "Invalid code. Check the email and try again.")
    }

    func testClearErrorRemovesTheMessageAndLeavesTheFormIntact() async {
        repo.requestResult = .failure(.network())
        let vm = makeViewModel()
        vm.onEmailChange("a@b.c")
        vm.sendCode()
        await vm.inFlight?.value
        XCTAssertEqual(vm.errorMessage, AppError.network().message)

        vm.clearError()

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.email, "a@b.c")
    }

    func testClearErrorIsHarmlessWhenThereIsNoError() {
        let vm = makeViewModel()
        vm.clearError()
        XCTAssertNil(vm.errorMessage)
    }
}
