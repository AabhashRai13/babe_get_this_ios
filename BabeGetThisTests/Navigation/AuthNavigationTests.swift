import XCTest
@testable import BabeGetThis

/// The auth back stack (NAV-03, one test per rule), list detail routing (NAV-01, ported from
/// Android `BgtNavGraphTest`) and Settings from the lists (NAV-05).
///
/// BgtNavGraphTest has 8 cases. Ported: the name round-trip (line 103). iOS pushes the list by
/// value, so there is no route encoding; the port checks that the pushed route carries the exact
/// id and name, which the detail screen uses as its title. Not ported: the four reminder cases
/// (lines 60, 70, 81, 92; reminders are out of iOS v1) and the three running-low create-list
/// request cases (lines 112, 122, 129: `showListCatalog`, `applyPendingCreateList`), since iOS has
/// no notification that asks the catalog to create a list.
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

        session.leaveAuth(AuthFlow(start: .login, below: .welcome).close())

        XCTAssertEqual(session.screen, .welcome)
        XCTAssertTrue(welcome.shouldShowWelcome(authState: auth.authState), "nothing recorded")
    }

    // MARK: - NAV-03: from a list's screen, Close and success both pop to the lists

    // Android `closeAuth()` / `leaveAuth()` run `popBackStack(SHOPPING_LIST, inclusive = false)`,
    // so auth opened from `ShoppingItemsScreen` (the live-share prompt) pops the list too.
    func testClosingAuthOpenedFromAListPopsToTheLists() {
        var navigation = ListsNavigation()
        navigation.open(Self.groceries)
        let flow = AuthFlow(start: .login, below: .list)

        navigation.leaveAuth(flow.close())

        XCTAssertEqual(flow.close(), .lists)
        XCTAssertEqual(navigation.path, [], "back on the lists, not on the list")
    }

    func testSigningInFromAListLandsOnTheLists() {
        var navigation = ListsNavigation()
        navigation.open(Self.groceries)
        var flow = AuthFlow(start: .register, below: .list)
        flow.showLogin()

        navigation.leaveAuth(flow.succeed())

        XCTAssertEqual(navigation.path, [])
    }

    // MARK: - NAV-03: Success lands on the lists and drops Welcome

    func testSuccessFromTheListsLandsOnTheLists() {
        var flow = AuthFlow(start: .login, below: .lists)
        flow.showRegister()

        XCTAssertEqual(flow.succeed(), .lists)
    }

    // Android `leaveAuth()` navigates to the lists and pops Welcome itself; it doesn't wait for
    // the auth state. So the exit alone must drop Welcome here too: the auth state is still
    // signed out when the session is told, and the screen must already be the lists.
    func testSuccessFromWelcomeLandsOnTheListsAndDropsWelcome() {
        let auth = signedOut()
        let session = StartSession(authState: auth, welcome: welcome)
        XCTAssertEqual(session.screen, .welcome)

        session.leaveAuth(AuthFlow(start: .login, below: .welcome).succeed())
        XCTAssertEqual(session.screen, .lists)

        // Signed in, then out again: Welcome is back (NAV-04), not stuck behind the earlier exit.
        auth.login(token: "t", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")
        auth.logout()
        XCTAssertEqual(session.screen, .welcome)
    }

    // A reset signs the user in, so it leaves auth entirely rather than popping to Login.
    func testAPasswordResetLeavesAuthForTheLists() {
        var flow = AuthFlow(start: .login, below: .welcome)
        flow.showForgotPassword()

        XCTAssertEqual(flow.succeed(), .lists)
    }

    // MARK: - NAV-01: list detail gets the id and the name; the title uses the passed name

    // BgtNavGraphTest "a name with slashes and question marks round-trips through the route".
    // The new list is pushed by value, so the route carries the exact name the detail screen
    // shows as its title.
    func testANameWithSlashesAndQuestionMarksRoundTripsToTheDetailScreen() async throws {
        let repository = NavigationListsRepository()
        let lists = ListsViewModel(repository: repository, authState: signedOut())
        var navigation = ListsNavigation()

        await lists.confirmCreate(named: "Dad's / BBQ? #1")
        // What ListsView does with the request: push it, then mark it handled.
        let request = try XCTUnwrap(lists.openListRequest)
        navigation.open(request)
        lists.didOpenRequestedList()

        XCTAssertEqual(navigation.path.map(\.id), [repository.createdId])
        XCTAssertEqual(navigation.path.map(\.name), ["Dad's / BBQ? #1"])
        XCTAssertNil(lists.openListRequest, "pushed once")
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
            let actions = lists.topBarActions

            // HOME-13 order: Join, Settings, then the account control.
            XCTAssertEqual(actions.prefix(2), [.join, .settings], "top bar in \(auth.authState)")
            XCTAssertEqual(actions.last, .account(lists.accountControl))
            lists.perform(.settings)
            XCTAssertTrue(lists.isSettingsPresented, "Settings from \(auth.authState)")
            XCTAssertNil(lists.authRoute, "Settings never asks for an account")
            XCTAssertFalse(lists.isProfilePresented)
        }
        XCTAssertEqual(SettingsView.title, "Settings")
    }

    // Sign-out clears the stack to Welcome (NAV-04), so the next sign-in doesn't land on a list
    // left over from the account that signed out.
    func testSigningOutClearsTheListScreens() {
        var navigation = ListsNavigation()
        navigation.open(Self.groceries)

        navigation.signedOut()

        XCTAssertEqual(navigation.path, [])
    }

    private static let groceries = ShoppingListSummary(id: "l1", name: "Groceries", totalItems: 0, pickedUpItems: 0,
                                                       createdAt: Date(timeIntervalSince1970: 0))
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
