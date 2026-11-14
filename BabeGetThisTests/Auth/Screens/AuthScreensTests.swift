import XCTest
@testable import BabeGetThis

/// Port of Android `AuthScreensTest` (27 cases, AUTH-11). Android renders each screen over its
/// real view model with a mocked repository. Here the same real view models run over
/// `ScreensAuthRepository`; what the screens render (labels, which fields, what scrolls) comes
/// from the `*ScreenCopy` the views are built from, and the routes go through `AuthFlow`.
@MainActor
final class AuthScreensTests: XCTestCase {
    private var repository: ScreensAuthRepository!
    private var succeeded = false

    override func setUp() async throws {
        repository = ScreensAuthRepository()
        succeeded = false
    }

    // MARK: - LoginScreen

    private func login() -> LoginViewModel {
        let viewModel = LoginViewModel(authRepository: repository, googleAuth: repository,
                                       googleTokens: ScreensClosedGoogleSheet())
        viewModel.onLoginSuccess = { [unowned self] in succeeded = true }
        return viewModel
    }

    private func submit(_ viewModel: LoginViewModel) async {
        viewModel.login()
        await viewModel.inFlight?.value
    }

    func testLoginShowsItsFieldsAndPrimaryAction() {
        XCTAssertEqual(LoginScreenCopy.fields, ["Email", "Password"])
        XCTAssertEqual(LoginScreenCopy.signIn, "Sign in")
        XCTAssertTrue(LoginScreenCopy.scrollingContent.contains(LoginScreenCopy.signIn))
    }

    // Rendering only: tapping it opens the real Google sheet, checked on a device.
    func testLoginOffersGoogleSignIn() {
        XCTAssertEqual(LoginScreenCopy.continueWithGoogle, "Continue with Google")
        XCTAssertTrue(LoginScreenCopy.scrollingContent.contains("Continue with Google"))
    }

    func testSignInIsDisabledUntilBothFieldsAreFilled() {
        let viewModel = login()

        XCTAssertFalse(viewModel.isFormValid)

        viewModel.onEmailChange("a@b.c")
        XCTAssertFalse(viewModel.isFormValid)

        viewModel.onPasswordChange("secret123")
        XCTAssertTrue(viewModel.isFormValid)
    }

    // Validation fires as you type, not only on submit.
    func testAMalformedEmailIsFlaggedInline() {
        let viewModel = login()

        viewModel.onEmailChange("not-an-email")

        XCTAssertEqual(viewModel.emailError, "Enter a valid email address")
    }

    func testAValidEmailClearsTheInlineError() {
        let viewModel = login()
        viewModel.onEmailChange("not-an-email")

        // Android types "@example.com" after the bad address.
        viewModel.onEmailChange("not-an-email@example.com")

        XCTAssertNil(viewModel.emailError)
    }

    func testSubmittingReachesTheRepositoryWithTheTypedCredentials() async {
        let viewModel = login()
        viewModel.onEmailChange("a@b.c")
        viewModel.onPasswordChange("secret123")

        await submit(viewModel)

        XCTAssertEqual(repository.loginCalls.count, 1)
        XCTAssertEqual(repository.loginCalls.first?.email, "a@b.c")
        XCTAssertEqual(repository.loginCalls.first?.password, "secret123")
    }

    func testASuccessfulLoginReportsSuccess() async {
        let viewModel = login()
        viewModel.onEmailChange("a@b.c")
        viewModel.onPasswordChange("secret123")

        await submit(viewModel)

        XCTAssertTrue(succeeded)
    }

    func testAFailedLoginShowsTheErrorAndDoesNotReportSuccess() async {
        repository.loginResult = .failure(.auth("Invalid email or password."))
        let viewModel = login()
        viewModel.onEmailChange("a@b.c")
        viewModel.onPasswordChange("wrongpass")

        await submit(viewModel)

        XCTAssertEqual(viewModel.errorMessage, "Invalid email or password.")
        XCTAssertFalse(succeeded)
    }

    func testAnOfflineLoginShowsTheNetworkMessage() async {
        repository.loginResult = .failure(.network())
        let viewModel = login()
        viewModel.onEmailChange("a@b.c")
        viewModel.onPasswordChange("secret123")

        await submit(viewModel)

        XCTAssertEqual(viewModel.errorMessage, AppError.network().message)
    }

    func testLoginOffersTheRegisterAndForgotPasswordRoutes() {
        XCTAssertEqual(LoginScreenCopy.signUp, "Sign up")
        XCTAssertEqual(LoginScreenCopy.forgotPassword, "Forgot password?")

        var toRegister = AuthFlow(start: .login, below: .lists)
        toRegister.showRegister()
        XCTAssertEqual(toRegister.current, .register)

        var toForgot = AuthFlow(start: .login, below: .lists)
        toForgot.showForgotPassword()
        XCTAssertEqual(toForgot.current, .forgotPassword)
    }

    // On a small phone the form alone fills the screen, so a "Sign up" at the end of the
    // scroll started out of view. New users have to find it.
    func testTheSignUpRouteStaysOutsideTheScrollingForm() {
        XCTAssertTrue(LoginScreenCopy.scrollingContent.contains(LoginScreenCopy.email))
        XCTAssertFalse(LoginScreenCopy.scrollingContent.contains(LoginScreenCopy.signUp))
        XCTAssertTrue(LoginScreenCopy.pinnedFooter.contains(LoginScreenCopy.signUp))
    }

    // MARK: - RegisterScreen

    private func register() -> RegisterViewModel {
        let viewModel = RegisterViewModel(authRepository: repository)
        viewModel.onRegisterSuccess = { [unowned self] in succeeded = true }
        return viewModel
    }

    private func fillRegisterForm(_ viewModel: RegisterViewModel,
                                  password: String = "secret123", confirm: String = "secret123") {
        viewModel.onNameChange("Aabhash")
        viewModel.onEmailChange("a@b.c")
        viewModel.onPasswordChange(password)
        viewModel.onConfirmPasswordChange(confirm)
    }

    private func submit(_ viewModel: RegisterViewModel) async {
        viewModel.register()
        await viewModel.inFlight?.value
    }

    func testRegisterShowsEveryField() {
        XCTAssertEqual(RegisterScreenCopy.fields, ["Your name", "Email", "Password", "Confirm password"])
    }

    func testCreateAccountIsDisabledUntilTheFormIsComplete() {
        let viewModel = register()

        XCTAssertEqual(RegisterScreenCopy.createAccount, "Create account")
        XCTAssertFalse(viewModel.isFormValid)

        fillRegisterForm(viewModel)

        XCTAssertTrue(viewModel.isFormValid)
    }

    func testAShortPasswordIsFlagged() {
        let viewModel = register()

        viewModel.onPasswordChange("abc")

        XCTAssertEqual(viewModel.passwordError, "Password must be at least 6 characters")
    }

    func testAMismatchedConfirmationIsFlaggedAndBlocksSubmission() async {
        let viewModel = register()

        fillRegisterForm(viewModel, password: "secret123", confirm: "different1")

        XCTAssertEqual(viewModel.confirmPasswordError, "Passwords do not match")
        XCTAssertFalse(viewModel.isFormValid)
        await submit(viewModel)
        XCTAssertTrue(repository.registerCalls.isEmpty)
    }

    func testRegisteringReachesTheRepositoryWithNameEmailAndPassword() async {
        let viewModel = register()
        fillRegisterForm(viewModel)

        await submit(viewModel)

        XCTAssertEqual(repository.registerCalls.count, 1)
        XCTAssertEqual(repository.registerCalls.first?.email, "a@b.c")
        XCTAssertEqual(repository.registerCalls.first?.password, "secret123")
        XCTAssertEqual(repository.registerCalls.first?.name, "Aabhash")
    }

    func testASignedInRegistrationReportsSuccess() async {
        let viewModel = register()
        fillRegisterForm(viewModel)

        await submit(viewModel)

        XCTAssertTrue(succeeded)
    }

    func testATakenEmailShowsTheError() async {
        repository.registerResult = .failure(.auth("That email is already registered."))
        let viewModel = register()
        fillRegisterForm(viewModel)

        await submit(viewModel)

        XCTAssertEqual(viewModel.errorMessage, "That email is already registered.")
        XCTAssertFalse(succeeded)
    }

    func testRegisterOffersTheSignInRoute() {
        XCTAssertEqual(RegisterScreenCopy.signIn, "Sign in")

        var flow = AuthFlow(start: .register, below: .lists)
        flow.showLogin()

        XCTAssertEqual(flow.current, .login)
    }

    // MARK: - ForgotPasswordScreen

    private func forgot() -> ForgotPasswordViewModel {
        let viewModel = ForgotPasswordViewModel(authRepository: repository)
        viewModel.onResetSuccess = { [unowned self] in succeeded = true }
        return viewModel
    }

    private func sendCode(_ viewModel: ForgotPasswordViewModel) async {
        viewModel.sendCode()
        await viewModel.inFlight?.value
    }

    func testForgotPasswordAsksForAnEmailFirst() {
        let viewModel = forgot()

        XCTAssertEqual(ForgotPasswordScreenCopy.fields(codeSent: viewModel.codeSent), ["Email"])
        XCTAssertEqual(ForgotPasswordScreenCopy.sendCode, "Send code")
    }

    func testSendCodeIsDisabledUntilTheEmailIsValid() {
        let viewModel = forgot()

        XCTAssertFalse(viewModel.isEmailValid)

        viewModel.onEmailChange("a@b.c")

        XCTAssertTrue(viewModel.isEmailValid)
    }

    func testSendingACodeReachesTheRepository() async {
        let viewModel = forgot()
        viewModel.onEmailChange("a@b.c")

        await sendCode(viewModel)

        XCTAssertEqual(repository.resetRequests, ["a@b.c"])
    }

    func testOnceTheCodeIsSentTheScreenAsksForItAndANewPassword() async {
        let viewModel = forgot()
        viewModel.onEmailChange("a@b.c")

        await sendCode(viewModel)

        XCTAssertEqual(ForgotPasswordScreenCopy.fields(codeSent: viewModel.codeSent), ["8-digit code", "New password"])
    }

    func testAFailedSendShowsTheErrorAndStaysOnTheEmailStep() async {
        repository.resetRequestResult = .failure(.network())
        let viewModel = forgot()
        viewModel.onEmailChange("a@b.c")

        await sendCode(viewModel)

        XCTAssertFalse(ForgotPasswordScreenCopy.fields(codeSent: viewModel.codeSent).contains("8-digit code"))
        XCTAssertEqual(viewModel.errorMessage, AppError.network().message)
    }

    // MARK: - AuthPromptDialog

    func testTheAuthPromptShowsTheCopyForTheFeatureThatRaisedIt() {
        XCTAssertEqual(AuthPromptContent.share.title, "Sign in to share")
        XCTAssertEqual(AuthPromptContent.share.body,
                       "Create an account to share lists with your partner and sync across devices.")
    }

    // Both actions close the prompt and then navigate: a prompt left open behind the auth
    // screen would be a real bug.
    func testTheAuthPromptRoutesToSignInAndClosesItself() {
        let lists = ListsViewModel()
        lists.pickVoice()
        XCTAssertEqual(lists.authPrompt, .voice)
        XCTAssertEqual(AuthPromptContent.confirmTitle, "Sign in")

        lists.promptSignIn()

        XCTAssertEqual(lists.authRoute, .login)
        XCTAssertNil(lists.authPrompt)
        XCTAssertNotEqual(lists.authRoute, .register, "must not also trigger register")
    }

    func testTheAuthPromptRoutesToRegisterAndClosesItself() {
        let lists = ListsViewModel()
        lists.pickVoice()
        XCTAssertEqual(AuthPromptContent.dismissTitle, "Create account")

        lists.promptCreateAccount()

        XCTAssertEqual(lists.authRoute, .register)
        XCTAssertNil(lists.authPrompt)
        XCTAssertNotEqual(lists.authRoute, .login, "must not also trigger login")
    }
}
