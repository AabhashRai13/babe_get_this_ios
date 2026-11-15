import XCTest
@testable import BabeGetThis

/// The adapters the app actually runs the profile on, against fakes of the layer below them
/// (not `FakeProfileAccount` / `FakeProfileSync`, which call back synchronously):
/// `AuthStateManager.observeProfile` (ProfileFieldsTracker) and `DeferredProfileSync`.
@MainActor
final class ProfileAdapterTests: XCTestCase {
    private var log: ProfileCallLog!

    override func setUp() async throws {
        try await super.setUp()
        log = ProfileCallLog()
    }

    /// Lets the tracker's next-main-actor-turn re-read run.
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    // MARK: - Account switch through the real AuthStateManager

    func testAnAccountSwitchRefreshesTheProfileThroughTheRealAuthStateManager() async {
        let authState = AuthStateManager(tokenStore: InMemoryTokenStore())
        authState.initialize()
        authState.login(token: "t1", userId: "alice-id", userName: "Alice", userEmail: "alice@x.com")
        let vm = ProfileViewModel(account: authState, auth: FakeProfileAuth(log: log),
                                  sync: FakeProfileSync(log: log), welcome: FakeProfileWelcome(log: log))
        XCTAssertEqual(vm.userName, "Alice")
        XCTAssertEqual(vm.userEmail, "alice@x.com")

        authState.logout()
        authState.login(token: "t2", userId: "bob-id", userName: "Bob", userEmail: "bob@x.com")
        await waitUntil { vm.userName == "Bob" }

        XCTAssertEqual(vm.userName, "Bob")
        XCTAssertEqual(vm.userEmail, "bob@x.com")
        XCTAssertEqual(vm.editedName, "Bob")
    }

    func testTheTrackerKeepsFollowingAfterTheFirstChange() async {
        let authState = AuthStateManager(tokenStore: InMemoryTokenStore())
        authState.initialize()
        authState.login(token: "t1", userId: "u1", userName: "Dev User", userEmail: "first@x.com")
        let vm = ProfileViewModel(account: authState, auth: FakeProfileAuth(log: log),
                                  sync: FakeProfileSync(log: log), welcome: FakeProfileWelcome(log: log))

        authState.updateName("Renamed")
        await waitUntil { vm.userName == "Renamed" }
        // Same name on the next account: only the email changes, and it must still arrive.
        authState.logout()
        authState.login(token: "t2", userId: "u2", userName: "Renamed", userEmail: "second@x.com")
        await waitUntil { vm.userEmail == "second@x.com" }

        XCTAssertEqual(vm.userName, "Renamed")
    }

    // MARK: - Sign-out through DeferredProfileSync over a real SyncEngine

    private func makeEngine(db: AppDatabase, remote: FakeSharedListRemote = FakeSharedListRemote()) -> SyncEngine {
        let userId = SyncTestUserId("user-1")
        return SyncEngine(
            listDao: db.lists, itemDao: db.items, remote: remote, syncPoints: FakeSyncPointStore(),
            ownership: FakeListOwnershipStore(), currentUserId: { userId.value },
            safeCall: SafeCall(reporter: SilentAppErrorReporter()))
    }

    private func insertAccountList(_ db: AppDatabase, id: String = "list-1") async throws {
        try await db.lists.insertList(ShoppingListRecord(
            id: id, name: "Groceries", createdAt: 500, updatedAt: 1_000, isLocked: false,
            shareCode: nil, deletedAt: nil, pendingSync: false, accountId: "user-1", onServer: true))
    }

    func testTheSignOutRunsAfterTheAccountListsAreGoneAndItsFailureComesBack() async throws {
        let db = try AppDatabase.inMemory()
        try await insertAccountList(db)
        let engine = makeEngine(db: db)
        let sync = DeferredProfileSync { engine }
        let seen = SignOutObservation()

        let result = await sync.evictAccountLists {
            seen.listsLeft = (try? await db.lists.listRaw(id: "list-1")) == nil ? 0 : 1
            return .failure(.network())
        }

        XCTAssertEqual(seen.listsLeft, 0, "the sign-out ran before the eviction finished")
        guard case .failure(let error) = result else { return XCTFail("expected the sign-out's failure") }
        XCTAssertEqual(.network, error.kind)
    }

    func testASuccessfulSignOutComesBackAsSuccess() async throws {
        let db = try AppDatabase.inMemory()
        try await insertAccountList(db)
        let engine = makeEngine(db: db)

        let result = await DeferredProfileSync { engine }.evictAccountLists { .success(()) }

        guard case .success = result else { return XCTFail("expected success, got \(result)") }
        let left = try await db.lists.listRaw(id: "list-1")
        XCTAssertNil(left)
    }

    func testWithoutAnEngineTheSignOutFailsAndNothingRuns() async {
        let ran = SignOutObservation()

        let result = await DeferredProfileSync { nil }.evictAccountLists {
            ran.listsLeft = -1
            return .success(())
        }

        guard case .failure(let error) = result else { return XCTFail("expected a failure") }
        XCTAssertEqual(.unknown, error.kind)
        XCTAssertNil(ran.listsLeft, "the sign-out must not run without the eviction")
    }

    func testAnUnreadableCountWarnsInsteadOfLosingEdits() async {
        let unsynced = await DeferredProfileSync { nil }.hasUnsyncedChanges(accountId: "user-1")

        XCTAssertTrue(unsynced)
    }

    func testTheRealProfileSignOutTakesTheListsOffThePhoneThenSignsOut() async throws {
        let db = try AppDatabase.inMemory()
        try await insertAccountList(db)
        let engine = makeEngine(db: db)
        let authState = AuthStateManager(tokenStore: InMemoryTokenStore())
        authState.initialize()
        authState.login(token: "t", userId: "user-1", userName: "Alice", userEmail: "alice@x.com")
        let auth = SigningOutProfileAuth(authState: authState, db: db)
        let vm = ProfileViewModel(account: authState, auth: auth, sync: DeferredProfileSync { engine },
                                  welcome: FakeProfileWelcome(log: log))

        vm.logout()
        await vm.inFlight?.value

        XCTAssertEqual(auth.listsLeftAtSignOut, 0)
        XCTAssertEqual(authState.authState, .unauthenticated)
        XCTAssertEqual(log.count("welcome.reset"), 1)
        XCTAssertNil(vm.toast)
    }
}

/// Signs the real `AuthStateManager` out, as `SupabaseAuthRepository.logout` does, and notes
/// whether the account's list was still on the phone at that moment.
private final class SigningOutProfileAuth: ProfileAuthenticating, @unchecked Sendable {
    private let authState: AuthStateManager
    private let db: AppDatabase
    private let seen = SignOutObservation()

    init(authState: AuthStateManager, db: AppDatabase) {
        self.authState = authState
        self.db = db
    }

    var listsLeftAtSignOut: Int? { seen.listsLeft }

    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError> {
        .failure(.unknown())
    }

    func logout() async -> Result<Void, AppError> {
        seen.listsLeft = (try? await db.lists.listRaw(id: "list-1")) == nil ? 0 : 1
        authState.logout()
        return .success(())
    }

    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError> {
        .failure(.unknown())
    }
}
