import XCTest
@testable import BabeGetThis

/// Port of Android `AuthScreensTest` (27 cases, AUTH-11). Android renders each screen over its
/// real view model with a mocked repository. Here the same real view models run over
/// `ScreensAuthRepository`. There is no UI test target, so the rendering cases check the lists
/// the views are built from (`LoginScreenCopy.fields` / `scrollingContent` / `pinnedFooter`,
/// `RegisterScreenCopy.fields`, `ForgotPasswordScreenCopy.fields(codeSent:)`), and the route
/// cases tap through the `*ScreenTaps` the views send every tap to.
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

    private func taps(_ viewModel: LoginViewModel, routes: ScreensRouteLog = ScreensRouteLog()) -> LoginScreenTaps {
        LoginScreenTaps(viewModel: viewModel, onRegister: { routes.record("register") },
                        onForgotPassword: { routes.record("forgotPassword") })
    }

    func testLoginShowsItsFieldsAndPrimaryAction() async {
        let viewModel = login()
        XCTAssertEqual(LoginScreenCopy.fields.map(\.label), ["Email", "Password"])
        XCTAssertTrue(LoginScreenCopy.scrollingContent.contains(.form), "the fields are in the form card")
        XCTAssertTrue(LoginScreenCopy.scrollingContent.contains(.signIn))
        XCTAssertEqual(LoginScreenElement.signIn.label, "Sign in")

        // The primary action follows the form and signs in with what was typed.
        XCTAssertFalse(viewModel.isEmailSignInEnabled)
        viewModel.onEmailChange("a@b.c")
        viewModel.onPasswordChange("secret123")
        XCTAssertTrue(viewModel.isEmailSignInEnabled)
        taps(viewModel).tap(.signIn)
        await viewModel.inFlight?.value
        XCTAssertEqual(repository.loginCalls.map(\.email), ["a@b.c"])
    }

    func testLoginOffersGoogleSignIn() async {
        let sheet = ScreensCountingGoogleSheet()
        let viewModel = LoginViewModel(authRepository: repository, googleAuth: repository, googleTokens: sheet)
        XCTAssertTrue(LoginScreenCopy.scrollingContent.contains(.google))
        XCTAssertEqual(LoginScreenElement.google.label, "Continue with Google")

        taps(viewModel).tap(.google)
        await viewModel.inFlight?.value

        XCTAssertEqual(sheet.requests, 1, "the button opens the Google sheet")
        XCTAssertTrue(repository.loginCalls.isEmpty)
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

    // Each route button calls its own callback, and only that one. AuthSheet's callbacks then
    // move the flow.
    func testLoginOffersTheRegisterAndForgotPasswordRoutes() {
        let routes = ScreensRouteLog()
        let screen = taps(login(), routes: routes)
        XCTAssertEqual(LoginScreenElement.signUp.label, "Sign up")
        XCTAssertEqual(LoginScreenElement.forgotPassword.label, "Forgot password?")

        screen.tap(.signUp)
        XCTAssertEqual(routes.taken, ["register"])
        screen.tap(.forgotPassword)
        XCTAssertEqual(routes.taken, ["register", "forgotPassword"])

        var flow = AuthFlow(start: .login, below: .lists)
        LoginScreenTaps(viewModel: login(), onRegister: { flow.showRegister() }, onForgotPassword: {}).tap(.signUp)
        XCTAssertEqual(flow.current, .register)
        XCTAssertTrue(repository.loginCalls.isEmpty, "a route never signs in")
    }

    // On a small phone the form alone fills the screen, so a "Sign up" at the end of the
    // scroll started out of view. New users have to find it. LoginView builds its ScrollView
    // from `scrollingContent` and the footer under it from `pinnedFooter`.
    func testTheSignUpRouteStaysOutsideTheScrollingForm() {
        XCTAssertTrue(LoginScreenCopy.scrollingContent.contains(.form), "Email scrolls")
        XCTAssertTrue(LoginScreenCopy.fields.contains(.email))
        XCTAssertFalse(LoginScreenCopy.scrollingContent.contains(.signUp))
        XCTAssertFalse(LoginScreenCopy.scrollingContent.contains(.noAccount))
        XCTAssertEqual(LoginScreenCopy.pinnedFooter, [.noAccount, .signUp])
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

    // RegisterView builds its form card from `RegisterScreenCopy.fields`; each field feeds the
    // view model input of the same name.
    func testRegisterShowsEveryField() {
        let viewModel = register()
        XCTAssertEqual(RegisterScreenCopy.fields.map(\.label), ["Your name", "Email", "Password", "Confirm password"])

        fillRegisterForm(viewModel)

        XCTAssertEqual([viewModel.name, viewModel.email, viewModel.password, viewModel.confirmPassword],
                       ["Aabhash", "a@b.c", "secret123", "secret123"])
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
        let viewModel = register()
        fillRegisterForm(viewModel)

        RegisterScreenTaps(viewModel: viewModel, onLogin: { flow.showLogin() }).tap(.signIn)

        XCTAssertEqual(flow.current, .login)
        XCTAssertNil(viewModel.inFlight, "the route doesn't submit the form")
        XCTAssertTrue(repository.registerCalls.isEmpty)
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

    // ForgotPasswordView shows `fields(codeSent:)` for the view model's step, then its action.
    func testForgotPasswordAsksForAnEmailFirst() {
        let viewModel = forgot()

        XCTAssertFalse(viewModel.codeSent)
        XCTAssertEqual(ForgotPasswordScreenCopy.fields(codeSent: viewModel.codeSent).map(\.label), ["Email"])
        XCTAssertEqual(ForgotPasswordScreenCopy.primaryAction(codeSent: viewModel.codeSent), "Send code")
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

        XCTAssertEqual(ForgotPasswordScreenCopy.fields(codeSent: viewModel.codeSent).map(\.label), ["8-digit code", "New password"])
        XCTAssertEqual(ForgotPasswordScreenCopy.primaryAction(codeSent: viewModel.codeSent), "Reset password")
    }

    func testAFailedSendShowsTheErrorAndStaysOnTheEmailStep() async {
        repository.resetRequestResult = .failure(.network())
        let viewModel = forgot()
        viewModel.onEmailChange("a@b.c")

        await sendCode(viewModel)

        XCTAssertEqual(ForgotPasswordScreenCopy.fields(codeSent: viewModel.codeSent), [.email])
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
