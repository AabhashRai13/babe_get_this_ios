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
}
