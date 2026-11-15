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

        container.start(syncEngine: TriggerFakeEngine(), network: network, sessionStatuses: .silent)

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

        container.start(syncEngine: engine, network: TriggerFakeNetwork(), sessionStatuses: .silent)

        let deadline = Date().addingTimeInterval(5)
        while engine.catchUpAccountCount == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(engine.authStates.contains(.authenticated(userId: "user-1")))
        XCTAssertEqual(engine.pushCount, 1)
        XCTAssertEqual(engine.catchUpAccountCount, 1)
    }

    // MARK: - Supabase's session reaches the app (AUTH-03, Android BabeGetThisApp.onCreate)

    private func waitUntil(_ condition: () -> Bool, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "timed out", line: line)
    }

    // Supabase rotates the access token about hourly. Without this, voice keeps sending the
    // login-time token, gets a 401 an hour later and signs the user out.
    func testAStartedContainerPersistsTheTokenSupabaseRotates() async throws {
        let tokens = signedInStore()
        let container = try makeContainer(tokenStore: tokens)
        let (statuses, supabase) = AsyncStream<SupabaseSessionStatus>.makeStream()
        container.start(syncEngine: TriggerFakeEngine(), network: TriggerFakeNetwork(), sessionStatuses: statuses)

        supabase.yield(.authenticated(accessToken: "rotated-token", userId: "user-1"))

        try await waitUntil { tokens.token() == "rotated-token" }
        XCTAssertEqual(container.authState.authState, .authenticated(userId: "user-1"))
    }

    // A refresh token revoked elsewhere: Supabase drops the session, and the app must stop
    // treating the account as live (its lists stay, decision 008).
    func testAStartedContainerMirrorsASessionSupabaseLost() async throws {
        let container = try makeContainer(tokenStore: signedInStore())
        let (statuses, supabase) = AsyncStream<SupabaseSessionStatus>.makeStream()
        container.start(syncEngine: TriggerFakeEngine(), network: TriggerFakeNetwork(), sessionStatuses: statuses)

        supabase.yield(.notAuthenticated)

        try await waitUntil { container.authState.authState == .sessionExpired(userId: "user-1") }
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
        container.start(syncEngine: engine, network: TriggerFakeNetwork(), sessionStatuses: .silent)
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

    /// Info.plist starts Analytics with collection off (FIREBASE_ANALYTICS_COLLECTION_ENABLED = NO),
    /// so start() is what turns it on for a user who hasn't opted out (TEL-02).
    func testStartAppliesTheStoredConsentToBothVendors() throws {
        let analytics = RecordingAnalytics()
        let crashReporter = RecordingCrashReporter()
        let consentStore = InMemoryTelemetryConsentStore()
        consentStore.crashReportingEnabled = false
        let container = AppContainer(
            config: .preview, authState: AuthStateManager(tokenStore: InMemoryTokenStore()),
            database: try AppDatabase.inMemory(),
            welcome: WelcomeRepository(defaults: defaults, isUpdateInstall: { false }),
            ownership: FakeListOwnershipStore(),
            telemetry: TelemetryVendors(analytics: analytics, crashReporter: crashReporter),
            telemetryConsentStore: consentStore)
        XCTAssertEqual([], analytics.collection, "building the container decides nothing")

        container.start(syncEngine: TriggerFakeEngine(), network: TriggerFakeNetwork(), sessionStatuses: .silent)

        XCTAssertEqual([true], analytics.collection)
        XCTAssertEqual([false], crashReporter.collection)
    }
}

private extension AsyncStream where Element == SupabaseSessionStatus {
    /// Supabase says nothing, so start() never opens a real client in tests.
    static var silent: AsyncStream<SupabaseSessionStatus> { AsyncStream { $0.finish() } }
}
