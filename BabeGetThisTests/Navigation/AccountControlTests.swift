import XCTest
@testable import BabeGetThis

/// The lists' top-bar account control (HOME-13) and the session-expired banner (HOME-14).
@MainActor
final class AccountControlTests: XCTestCase {
    private var auth: AuthStateManager!

    private func lists(userId: String? = nil, token: String? = nil,
                       name: String? = nil, email: String? = nil) -> ListsViewModel {
        let tokens = InMemoryTokenStore()
        if let userId { tokens.saveUserId(userId) }
        if let token { tokens.saveToken(token) }
        if let name { tokens.saveUserName(name) }
        if let email { tokens.saveUserEmail(email) }
        auth = AuthStateManager(tokenStore: tokens)
        auth.initialize()
        return ListsViewModel(repository: NavigationListsRepository(), authState: auth)
    }

    // MARK: HOME-13

    func testAGuestGetsTheSignInPillWhichOpensLogin() {
        let vm = lists()

        XCTAssertEqual(vm.accountControl, .signIn)
        XCTAssertEqual(ListsViewModel.signInPill, "Sign in")
        vm.tapAccountControl()
        XCTAssertEqual(vm.authRoute, .login)
        XCTAssertFalse(vm.isProfilePresented)
    }

    func testASignedInAccountGetsTheInitialOfItsName() {
        let vm = lists(userId: "u1", token: "t", name: "aabhash", email: "z@b.c")

        XCTAssertEqual(vm.accountControl, .avatar(initial: "A"))
    }

    // Android `AccountAction`: `userName?.trim()?.firstOrNull()`, else a person glyph. Never
    // the email.
    func testWithoutANameTheAvatarShowsAPersonGlyphNotTheEmail() {
        let noName = lists(userId: "u1", token: "t", email: "zoe@b.c")
        let blankName = lists(userId: "u1", token: "t", name: "   ", email: "zoe@b.c")

        XCTAssertEqual(noName.accountControl, .avatar(initial: nil))
        XCTAssertEqual(blankName.accountControl, .avatar(initial: nil))
        XCTAssertEqual(ListsViewModel.initial(name: "  ann "), "A")
    }

    func testAnExpiredSessionKeepsTheAvatar() {
        let vm = lists(userId: "u1", name: "Aabhash")

        XCTAssertEqual(vm.accountControl, .avatar(initial: "A"))
    }

    func testTheAvatarOpensTheProfileSheetWithNameAndEmail() {
        let vm = lists(userId: "u1", token: "t", name: "Aabhash", email: "a@b.c")

        vm.tapAccountControl()

        XCTAssertTrue(vm.isProfilePresented)
        XCTAssertNil(vm.authRoute)
        XCTAssertEqual(vm.profileName, "Aabhash")
        XCTAssertEqual(vm.profileEmail, "a@b.c")
    }

    // Android closes the sheet when the account goes (`LaunchedEffect(hasAccount)` in
    // ShoppingListScreen.kt). Here the lists screen is torn down on sign-out while its view model
    // lives on, so the request itself must go, or the sheet pops up again on the next sign-in.
    func testSigningOutClosesTheProfileSheetAndItStaysClosedOnTheNextSignIn() {
        let vm = lists(userId: "u1", token: "t", name: "Aabhash", email: "a@b.c")
        vm.tapAccountControl()
        XCTAssertTrue(vm.isProfilePresented)

        auth.logout()
        XCTAssertFalse(vm.isProfilePresented)
        auth.login(token: "t2", userId: "u1", userName: "Aabhash", userEmail: "a@b.c")

        XCTAssertFalse(vm.isProfilePresented)
        XCTAssertFalse(vm.isSheetPresented, "nothing holds back the adoption notice")
        XCTAssertNil(vm.authRoute)
    }

    // A sign-out clears the stack to Welcome (NAV-04), so nothing opened over the lists before
    // it comes back after the next sign-in.
    func testSigningOutDropsEverythingOpenedOverTheLists() {
        let vm = lists(userId: "u1", token: "t", name: "Aabhash")
        vm.openSettings()
        vm.startCreating()
        vm.pickType()
        vm.isVoicePresented = true

        auth.logout()
        auth.login(token: "t2", userId: "u2", userName: "Bo", userEmail: "b@c.d")

        XCTAssertFalse(vm.isSettingsPresented)
        XCTAssertFalse(vm.isNamingList)
        XCTAssertFalse(vm.isVoicePresented)
        XCTAssertFalse(vm.isChooserPresented)
        XCTAssertNil(vm.authPrompt)
    }

    // A lost session keeps the account, so it closes nothing (NAV-04: SessionExpired stays put).
    func testALostSessionKeepsTheProfileSheetAndSettingsOpen() {
        let vm = lists(userId: "u1", token: "t", name: "Aabhash")
        vm.tapAccountControl()
        vm.openSettings()

        auth.expireSession()

        XCTAssertTrue(vm.isProfilePresented)
        XCTAssertTrue(vm.isSettingsPresented)
    }

    // MARK: HOME-14

    func testTheBannerShowsOnlyWhileTheSessionIsExpired() {
        XCTAssertFalse(lists().isSessionExpired)
        XCTAssertFalse(lists(userId: "u1", token: "t").isSessionExpired)
        XCTAssertTrue(lists(userId: "u1").isSessionExpired)
        XCTAssertEqual(ListsViewModel.sessionExpiredMessage,
                       "You've been signed out. Sign in again to keep your lists in sync.")
        XCTAssertEqual(ListsViewModel.sessionExpiredAction, "Sign in")
    }

    func testTheBannerSignInOpensLogin() {
        let vm = lists(userId: "u1")

        vm.signInAgain()

        XCTAssertEqual(vm.authRoute, .login)
    }
}
