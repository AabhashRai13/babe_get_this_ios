import XCTest
@testable import BabeGetThis

/// App start (APP-05): the sync trigger is registered and the auth state restored before the
/// first screen decision.
@MainActor
final class AppStartTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "app-start-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeContainer(tokenStore: InMemoryTokenStore) throws -> AppContainer {
        AppContainer(config: .preview,
                     authState: AuthStateManager(tokenStore: tokenStore),
                     database: try AppDatabase.inMemory(),
                     welcome: WelcomeRepository(defaults: defaults, isUpdateInstall: { false }),
                     ownership: FakeListOwnershipStore())
    }

    private func signedInStore() -> InMemoryTokenStore {
        let store = InMemoryTokenStore()
        store.saveToken("token")
        store.saveUserId("user-1")
        store.saveUserName("User")
        store.saveUserEmail("user@example.com")
        return store
    }

    func testAuthIsRestoredBeforeTheFirstScreenDecision() throws {
        let container = try makeContainer(tokenStore: signedInStore())
        let network = TriggerFakeNetwork()
        XCTAssertEqual(container.session.screen, .launch)

        container.start(syncEngine: TriggerFakeEngine(), network: network)

        // Synchronously, before any view reads the screen: signed in goes straight to the
        // lists, never through Welcome, and the trigger is already listening.
        XCTAssertEqual(container.authState.authState, .authenticated(userId: "user-1"))
        XCTAssertEqual(container.session.screen, .lists)
        XCTAssertTrue(network.isStarted)
    }

    func testLaunchingSignedInKicksASync() async throws {
        let container = try makeContainer(tokenStore: signedInStore())
        let engine = TriggerFakeEngine()
        engine.answerOnAuthState { if case .authenticated = $0 { true } else { false } }

        container.start(syncEngine: engine, network: TriggerFakeNetwork())

        let deadline = Date().addingTimeInterval(5)
        while engine.catchUpAccountCount == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(engine.authStates.contains(.authenticated(userId: "user-1")))
        XCTAssertEqual(engine.pushCount, 1)
        XCTAssertEqual(engine.catchUpAccountCount, 1)
    }

    // MARK: - The list repository's catch-up (DATA-06) goes through the start gate

    private func seedEmptyListOnServer(_ container: AppContainer) async throws {
        try await container.database.lists.insertList(TestData.listEntity(id: "L1").with {
            $0.accountId = "user-1"
            $0.onServer = true
        })
    }

    func testAStartedContainerCatchesUpThroughTheInjectedEngine() async throws {
        let container = try makeContainer(tokenStore: signedInStore())
        let engine = TriggerFakeEngine()
        container.start(syncEngine: engine, network: TriggerFakeNetwork())
        try await seedEmptyListOnServer(container)

        let result = try await container.listRepository.deleteListIfEmpty(listId: "L1")

        XCTAssertEqual(engine.catchUpListIds, ["L1"])
        XCTAssertEqual(try result.get(), true, "the server agreed it was empty, so it went")
    }

    func testAnUnstartedContainerFailsTheCatchUpAndKeepsTheList() async throws {
        let container = try makeContainer(tokenStore: signedInStore())
        // A live session without start(): the repository asks, and the gate says no.
        container.authState.initialize()
        XCTAssertEqual(container.authState.liveSessionUserId, "user-1")
        try await seedEmptyListOnServer(container)

        let result = try await container.listRepository.deleteListIfEmpty(listId: "L1")

        XCTAssertEqual(try result.get(), false)
        let kept = try await container.database.lists.listRaw(id: "L1")
        XCTAssertNotNil(kept)
        XCTAssertNil(kept?.deletedAt)
    }
}
