import XCTest
@testable import BabeGetThis

/// The lists' top-bar account control (HOME-13) and the session-expired banner (HOME-14).
@MainActor
final class AccountControlTests: XCTestCase {
    private func lists(userId: String? = nil, token: String? = nil,
                       name: String? = nil, email: String? = nil) -> ListsViewModel {
        let tokens = InMemoryTokenStore()
        if let userId { tokens.saveUserId(userId) }
        if let token { tokens.saveToken(token) }
        if let name { tokens.saveUserName(name) }
        if let email { tokens.saveUserEmail(email) }
        let auth = AuthStateManager(tokenStore: tokens)
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
