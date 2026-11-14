import XCTest
@testable import BabeGetThis

/// Port of Android `ProfileViewModelTest`, every case by name.
@MainActor
final class ProfileViewModelTests: XCTestCase {
    private var log: ProfileCallLog!
    private var account: FakeProfileAccount!
    private var auth: FakeProfileAuth!
    private var sync: FakeProfileSync!
    private var welcome: FakeProfileWelcome!

    override func setUp() {
        log = ProfileCallLog()
        // Logged out by default (null name and email), owner "u1", like the Android fixture.
        account = FakeProfileAccount()
        auth = FakeProfileAuth(log: log)
        sync = FakeProfileSync(log: log)
        welcome = FakeProfileWelcome(log: log)
    }

    private func buildViewModel() -> ProfileViewModel {
        ProfileViewModel(account: account, auth: auth, sync: sync, welcome: welcome)
    }

    // The shared fixture seeds a null name/email (logged out), which the existing tests depend
    // on. Name-editing tests need somebody signed in, so they seed their own.
    private func buildSignedIn(name: String = "Aabhash") -> ProfileViewModel {
        account = FakeProfileAccount(userName: name, userEmail: "a@b.c")
        return buildViewModel()
    }

    private func settle(_ vm: ProfileViewModel) async {
        await vm.inFlight?.value
    }

    func testSuccessfulAccountDeletionEmitsAConfirmationToast() async {
        auth.deleteResult = .success(())
        let viewModel = buildViewModel()

        viewModel.deleteAccount()
        await settle(viewModel)

        XCTAssertEqual(viewModel.toast?.message, "Your account has been deleted")
        XCTAssertFalse(viewModel.isDeletingAccount)
    }

    func testSwitchingAccountsRefreshesTheDisplayedNameAndEmail() {
        account = FakeProfileAccount(userName: "Alice", userEmail: "alice@x.com")
        let viewModel = buildViewModel()
        XCTAssertEqual(viewModel.userName, "Alice")
        XCTAssertEqual(viewModel.userEmail, "alice@x.com")

        // Log out, then log in as a different account.
        account.userName = nil
        account.userEmail = nil
        account.userName = "Bob"
        account.userEmail = "bob@x.com"

        XCTAssertEqual(viewModel.userName, "Bob")
        XCTAssertEqual(viewModel.userEmail, "bob@x.com")
        XCTAssertEqual(viewModel.editedName, "Bob")
    }

    func testEmailRefreshIsReflectedEvenWhenTwoAccountsShareADisplayName() {
        account = FakeProfileAccount(userName: "Dev User", userEmail: "first@x.com")
        let viewModel = buildViewModel()
        XCTAssertEqual(viewModel.userEmail, "first@x.com")

        // Same name on the next account: only the email changes.
        account.userEmail = "second@x.com"

        XCTAssertEqual(viewModel.userEmail, "second@x.com")
    }

    func testFailedAccountDeletionSurfacesTheErrorAndStopsTheSpinner() async {
        auth.deleteResult = .failure(.network())
        let viewModel = buildViewModel()

        viewModel.deleteAccount()
        await settle(viewModel)

        XCTAssertEqual(viewModel.toast?.message, AppError.network().message)
        XCTAssertFalse(viewModel.isDeletingAccount)
    }

    // MARK: - onNameChanged / hasNameChanged

    func testOnNameChangedUpdatesOnlyTheEditedName() {
        let vm = buildSignedIn()

        vm.onNameChanged("Renamed")

        XCTAssertEqual(vm.editedName, "Renamed")
        XCTAssertEqual(vm.userName, "Aabhash")
    }

    func testHasNameChangedIsFalseUntilTheNameActuallyDiffers() {
        let vm = buildSignedIn()
        XCTAssertFalse(vm.hasNameChanged)

        vm.onNameChanged("Aabhash")
        XCTAssertFalse(vm.hasNameChanged)

        vm.onNameChanged("Renamed")
        XCTAssertTrue(vm.hasNameChanged)
    }

    func testABlankEditedNameIsNotAChange() {
        let vm = buildSignedIn()

        vm.onNameChanged("   ")

        XCTAssertFalse(vm.hasNameChanged)
    }

    // MARK: - saveName

    func testSaveNameRejectsABlankNameWithoutCallingTheRepository() async {
        let vm = buildSignedIn()
        vm.onNameChanged("   ")

        vm.saveName()
        await settle(vm)

        XCTAssertEqual(vm.toast?.message, "Name cannot be empty")
        XCTAssertEqual(auth.updateNameCalls, [])
        XCTAssertFalse(vm.isSaving)
    }

    func testSaveNameTrimsBeforeSending() async {
        auth.updateNameResult = .success(AuthUser(id: "u1", email: "a@b.c", name: "Renamed"))
        let vm = buildSignedIn()
        vm.onNameChanged("  Renamed  ")

        vm.saveName()
        await settle(vm)

        XCTAssertEqual(auth.updateNameCalls, ["Renamed"])
    }

    func testASuccessfulSaveAdoptsTheReturnedNameAndConfirms() async {
        auth.updateNameResult = .success(AuthUser(id: "u1", email: "a@b.c", name: "Renamed"))
        let vm = buildSignedIn()
        vm.onNameChanged("Renamed")

        vm.saveName()
        await settle(vm)

        XCTAssertEqual(vm.toast?.message, "Name updated")
        XCTAssertEqual(vm.userName, "Renamed")
        XCTAssertEqual(vm.editedName, "Renamed")
        XCTAssertFalse(vm.isSaving)
        XCTAssertFalse(vm.hasNameChanged, "nothing left to save")
    }

    func testAFailedSaveSurfacesTheErrorAndKeepsTheEdit() async {
        auth.updateNameResult = .failure(.network())
        let vm = buildSignedIn()
        vm.onNameChanged("Renamed")

        vm.saveName()
        await settle(vm)

        XCTAssertEqual(vm.toast?.message, AppError.network().message)
        XCTAssertEqual(vm.userName, "Aabhash")
        XCTAssertEqual(vm.editedName, "Renamed", "the user's typing must not be discarded")
        XCTAssertFalse(vm.isSaving)
    }

    // Pinned rather than endorsed: saveName does not consult hasNameChanged, so saving an
    // untouched name still round-trips to the backend.
    func testSavingAnUnchangedNameStillCallsTheRepository() async {
        auth.updateNameResult = .success(AuthUser(id: "u1", email: "a@b.c", name: "Aabhash"))
        let vm = buildSignedIn()

        vm.saveName()
        await settle(vm)

        XCTAssertEqual(auth.updateNameCalls, ["Aabhash"])
    }

    // MARK: - logout

    func testLogoutClearsTheSessionAndStopsTheSpinner() async {
        auth.logoutResult = .success(())
        let vm = buildViewModel()

        vm.logout()
        await settle(vm)

        XCTAssertEqual(log.count("logout"), 1)
        XCTAssertFalse(vm.isLoggingOut)
    }

    // logout() always succeeds through SupabaseAuthRepository; covered anyway because the view
    // model takes a protocol and another implementation is free to fail.
    func testAFailingLogoutSurfacesTheError() async {
        auth.logoutResult = .failure(.unknown())
        let vm = buildViewModel()

        vm.logout()
        await settle(vm)

        XCTAssertEqual(vm.toast?.message, AppError.unknown().message)
        XCTAssertFalse(vm.isLoggingOut)
    }

    // MARK: - account-list eviction (docs/technical-decisions/008)

    func testLogoutEvictsTheAccountsListsBeforeTheSessionIsDestroyed() async {
        let vm = buildViewModel()

        vm.logout()
        await settle(vm)

        // The final push inside the eviction still has a session.
        XCTAssertTrue(log.contains(inOrder: ["push", "evictAccountLists", "logout"]), "\(log.calls)")
    }

    // Push while the session still exists, delete the account, and only then take its lists
    // off the phone: a deletion that fails must leave every list and unsynced edit in place.
    func testDeleteAccountPushesFirstAndEvictsTheListsOnlyAfterTheAccountIsGone() async {
        auth.deleteResult = .success(())
        let vm = buildViewModel()

        vm.deleteAccount()
        await settle(vm)

        XCTAssertTrue(log.contains(inOrder: ["push", "deleteAccount", "evictAccountLists"]), "\(log.calls)")
    }

    func testAFailedAccountDeletionKeepsEveryListOnThePhone() async {
        auth.deleteResult = .failure(.network())
        let vm = buildViewModel()

        vm.deleteAccount()
        await settle(vm)

        XCTAssertEqual(log.count("evictAccountLists"), 0)
    }

    // MARK: - signing out with changes that never reached the server

    func testSigningOutWithEverythingSyncedAlsoResetsWelcome() async {
        auth.logoutResult = .success(())
        let vm = buildViewModel()

        vm.logout()
        await settle(vm)

        XCTAssertEqual(log.count("welcome.reset"), 1)
        XCTAssertFalse(vm.showUnsyncedSignOutWarning)
    }

    func testSigningOutWithUnsyncedChangesShowsTheWarningAndDoesNothingElse() async {
        sync.unsyncedAccounts = ["u1"]
        let vm = buildViewModel()

        vm.logout()
        await settle(vm)

        XCTAssertTrue(vm.showUnsyncedSignOutWarning)
        XCTAssertFalse(vm.isLoggingOut)
        XCTAssertEqual(log.count("evictAccountLists"), 0)
        XCTAssertEqual(log.count("logout"), 0)
        XCTAssertEqual(log.count("welcome.reset"), 0)
    }

    func testSignOutAnywayCompletesTheSignOut() async {
        sync.unsyncedAccounts = ["u1"]
        auth.logoutResult = .success(())
        let vm = buildViewModel()
        vm.logout()
        await settle(vm)

        vm.confirmSignOutAnyway()
        XCTAssertFalse(vm.showUnsyncedSignOutWarning)
        await settle(vm)

        XCTAssertFalse(vm.showUnsyncedSignOutWarning)
        XCTAssertTrue(log.contains(inOrder: ["evictAccountLists", "logout"]), "\(log.calls)")
        XCTAssertEqual(log.count("welcome.reset"), 1)
        XCTAssertFalse(vm.isLoggingOut)
    }

    func testDismissingTheWarningKeepsTheUserSignedIn() async {
        sync.unsyncedAccounts = ["u1"]
        let vm = buildViewModel()
        vm.logout()
        await settle(vm)

        vm.dismissUnsyncedSignOutWarning()

        XCTAssertFalse(vm.showUnsyncedSignOutWarning)
        XCTAssertEqual(log.count("logout"), 0)
    }

    func testAFailedSignOutLeavesWelcomeAlone() async {
        auth.logoutResult = .failure(.unknown())
        let vm = buildViewModel()

        vm.logout()
        await settle(vm)

        XCTAssertEqual(log.count("welcome.reset"), 0)
    }

    // After a lost session the push is a no-op, which is exactly when the queue is full: the
    // warning has to count the OWNER's rows, not a live session's.
    func testSigningOutAfterALostSessionStillWarnsAboutQueuedChanges() async {
        sync.unsyncedAccounts = ["u1"]
        let vm = buildViewModel()

        vm.logout()
        await settle(vm)

        XCTAssertEqual(sync.unsyncedQueries, ["u1"])
        XCTAssertTrue(vm.showUnsyncedSignOutWarning)
        XCTAssertEqual(log.count("logout"), 0)
    }

    func testWithNoAccountOnThePhoneThereIsNothingToWarnAbout() async {
        account.owner = nil
        auth.logoutResult = .success(())
        let vm = buildViewModel()

        vm.logout()
        await settle(vm)

        XCTAssertEqual(log.count("hasUnsyncedChanges"), 0)
        XCTAssertEqual(log.count("logout"), 1)
    }

    func testAFailedEvictionSurfacesTheErrorAndLeavesWelcomeAlone() async {
        sync.evictionFailure = .unknown()
        let vm = buildViewModel()

        vm.logout()
        await settle(vm)

        XCTAssertEqual(vm.toast?.message, AppError.unknown().message)
        XCTAssertEqual(log.count("welcome.reset"), 0)
        XCTAssertFalse(vm.isLoggingOut)
    }

    func testDeletingTheAccountResetsWelcome() async {
        auth.deleteResult = .success(())
        let vm = buildViewModel()

        vm.deleteAccount()
        await settle(vm)

        XCTAssertEqual(log.count("welcome.reset"), 1)
    }

    func testAFailedDeletionLeavesWelcomeAlone() async {
        auth.deleteResult = .failure(.unknown())
        let vm = buildViewModel()

        vm.deleteAccount()
        await settle(vm)

        XCTAssertEqual(log.count("welcome.reset"), 0)
    }
}
