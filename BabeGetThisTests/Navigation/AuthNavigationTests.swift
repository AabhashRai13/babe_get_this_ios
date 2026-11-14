import XCTest
@testable import BabeGetThis

/// The auth back stack (NAV-03, one test per rule), list detail routing (NAV-01, ported from
/// Android `BgtNavGraphTest`) and Settings from the lists (NAV-05).
///
/// Not ported from BgtNavGraphTest: the five reminder cases (reminders are out of iOS v1) and
/// the three running-low create-list request cases (`showListCatalog`, `applyPendingCreateList`):
/// iOS has no notification that asks the catalog to create a list.
@MainActor
final class AuthNavigationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var welcome: WelcomeRepository!

    override func setUp() {
        super.setUp()
        suiteName = "auth-navigation-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        welcome = WelcomeRepository(defaults: defaults, isUpdateInstall: { false })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func signedOut() -> AuthStateManager {
        let auth = AuthStateManager(tokenStore: InMemoryTokenStore())
        auth.initialize()
        return auth
    }

    // MARK: - NAV-03: Login and Register replace each other; Forgot stacks on Login

    func testRegisterReplacesLogin() {
        var flow = AuthFlow(start: .login, below: .lists)

        flow.showRegister()

        XCTAssertEqual(flow.stack, [.register])
    }

    func testLoginReplacesRegister() {
        var flow = AuthFlow(start: .register, below: .lists)

        flow.showLogin()

        XCTAssertEqual(flow.stack, [.login])
    }

    func testSwappingBackAndForthNeverStacksUp() {
        var flow = AuthFlow(start: .login, below: .welcome)

        for _ in 0..<3 {
            flow.showRegister()
            flow.showLogin()
        }

        XCTAssertEqual(flow.stack, [.login])
    }

    func testForgotPasswordStacksOnLogin() {
        var flow = AuthFlow(start: .login, below: .lists)

        flow.showForgotPassword()

        XCTAssertEqual(flow.stack, [.login, .forgotPassword])
        XCTAssertTrue(flow.isShowingForgotPassword)
    }

    func testBackFromForgotPasswordReturnsToLogin() {
        var flow = AuthFlow(start: .login, below: .lists)
        flow.showForgotPassword()

        let exit = flow.back()

        XCTAssertNil(exit, "back from Forgot password stays in auth")
        XCTAssertEqual(flow.stack, [.login])
    }

    func testForgotPasswordIsOnlyReachedFromLogin() {
        var flow = AuthFlow(start: .register, below: .lists)

        flow.showForgotPassword()

        XCTAssertEqual(flow.stack, [.register])
    }

    // MARK: - NAV-03: Close pops to the lists (or to Welcome if the lists aren't below)

    func testCloseReturnsToTheListsWhenTheyAreBelow() {
        var flow = AuthFlow(start: .login, below: .lists)
        flow.showRegister()

        XCTAssertEqual(flow.close(), .lists)
    }

    func testCloseReturnsToWelcomeWhenTheListsAreNotBelow() {
        let flow = AuthFlow(start: .login, below: .welcome)

        XCTAssertEqual(flow.close(), .welcome)
    }

    func testBackOnTheFirstAuthScreenClosesAuth() {
        var fromLists = AuthFlow(start: .login, below: .lists)
        var fromWelcome = AuthFlow(start: .login, below: .welcome)

        XCTAssertEqual(fromLists.back(), .lists)
        XCTAssertEqual(fromWelcome.back(), .welcome)
    }

    // Welcome's "Sign in" persists nothing, so closing auth shows Welcome again.
    func testClosingAuthOpenedFromWelcomeKeepsWelcome() {
        let auth = signedOut()
        let session = StartSession(authState: auth, welcome: welcome)
        XCTAssertEqual(session.screen, .welcome)
        WelcomeViewModel(welcome: welcome).onSignIn()

        let exit = AuthFlow(start: .login, below: .welcome).close()
        if exit == .lists { session.refresh() }

        XCTAssertEqual(exit, .welcome)
        XCTAssertEqual(session.screen, .welcome)
    }

    // MARK: - NAV-03: Success lands on the lists and drops Welcome

    func testSuccessFromTheListsLandsOnTheLists() {
        var flow = AuthFlow(start: .login, below: .lists)
        flow.showRegister()

        XCTAssertEqual(flow.succeed(), .lists)
    }

    func testSuccessFromWelcomeLandsOnTheListsAndDropsWelcome() {
        let auth = signedOut()
        let session = StartSession(authState: auth, welcome: welcome)
        XCTAssertEqual(session.screen, .welcome)
        let flow = AuthFlow(start: .login, below: .welcome)

        auth.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        let exit = flow.succeed()
        if exit == .lists { session.refresh() }

        XCTAssertEqual(exit, .lists)
        XCTAssertEqual(session.screen, .lists)
    }

    // A reset signs the user in, so it leaves auth entirely rather than popping to Login.
    func testAPasswordResetLeavesAuthForTheLists() {
        var flow = AuthFlow(start: .login, below: .welcome)
        flow.showForgotPassword()

        XCTAssertEqual(flow.succeed(), .lists)
    }

    // MARK: - NAV-01: list detail gets the id and the name; the title uses the passed name

    // BgtNavGraphTest "a name with slashes and question marks round-trips through the route".
    func testANameWithSlashesAndQuestionMarksRoundTripsToTheDetailScreen() async throws {
        let repository = NavigationListsRepository()
        let lists = ListsViewModel(repository: repository, authState: signedOut())

        await lists.confirmCreate(named: "Dad's / BBQ? #1")

        let opened = try XCTUnwrap(lists.openListRequest)
        XCTAssertEqual(opened.id, repository.createdId)
        XCTAssertEqual(opened.name, "Dad's / BBQ? #1")
    }

    // MARK: - NAV-05: Settings is reachable from the lists in every auth state

    func testSettingsIsReachableInEveryAuthState() {
        let expired = InMemoryTokenStore()
        expired.saveUserId("u1")
        let signedIn = InMemoryTokenStore()
        signedIn.saveUserId("u1")
        signedIn.saveToken("t")

        for tokens in [InMemoryTokenStore(), signedIn, expired] {
            let auth = AuthStateManager(tokenStore: tokens)
            auth.initialize()
            let lists = ListsViewModel(repository: NavigationListsRepository(), authState: auth)

            lists.openSettings()

            XCTAssertTrue(lists.isSettingsPresented, "Settings from \(auth.authState)")
        }
        XCTAssertEqual(SettingsView.title, "Settings")
    }
}

/// Creates lists in memory; nothing else is used by these tests.
final class NavigationListsRepository: ListsRepositoryProviding, @unchecked Sendable {
    let createdId = "created-list"

    func allLists() -> AsyncThrowingStream<[ShoppingList], any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func createList(name: String) async throws -> Result<String, AppError> { .success(createdId) }

    func createListWithItems(name: String, drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        .success(createdId)
    }

    func updateListName(listId: String, newName: String) async throws -> Result<Void, AppError> { .success(()) }

    func deleteListAndCaptureItems(listId: String) async throws -> Result<[ShoppingItemRecord], AppError> {
        .success([])
    }

    func restoreListWithItems(list: ShoppingList, items: [ShoppingItemRecord]) async throws -> Result<Void, AppError> {
        .success(())
    }
}
