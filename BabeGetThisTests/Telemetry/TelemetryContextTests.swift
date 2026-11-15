import XCTest
@testable import BabeGetThis

/// Port of Android's TelemetryContextTest. The data-shape keys come from COUNT queries, which
/// are throttled to one refresh per 30 s window; the per-screen keys are set every time.
final class TelemetryContextTests: XCTestCase {
    private let analytics = RecordingAnalytics()
    private let crashReporter = RecordingCrashReporter()
    private let consent = RecordingConsent()
    private let dataShape = CountingDataShape()
    private let clock = ManualClock()
    private let network = FakeOnline()

    private lazy var context = TelemetryContext(
        analytics: analytics, crashReporter: crashReporter,
        isOnline: { [network] in network.online }, consent: consent, dataShape: dataShape,
        flavor: "dev", dataShapeRefresh: Throttle(windowMillis: 30_000) { [clock] in clock.now })

    func testAppStartAppliesThePersistedConsentBeforeAnythingIsRecorded() {
        context.onAppStart()

        XCTAssertEqual(1, consent.applied)
        XCTAssertEqual(["dev"], crashReporter.values(for: .flavor))
        XCTAssertEqual(["signed_out"], crashReporter.values(for: .authState))
    }

    func testASignedInUserIsIdentifiedByIdInBothAnalyticsAndCrashReports() {
        context.onUserChanged("user-1")

        XCTAssertEqual(["user-1"], analytics.users)
        XCTAssertEqual(["user-1"], crashReporter.users)
        XCTAssertEqual(["signed_in"], crashReporter.values(for: .authState))
    }

    func testSigningOutClearsTheIdentity() {
        context.onUserChanged(nil)

        XCTAssertEqual([nil], crashReporter.users)
        XCTAssertEqual(["signed_out"], crashReporter.values(for: .authState))
    }

    func testAnOfflineScreenChangeRecordsTheNetworkStateAsOffline() async {
        network.online = false

        await context.onScreen(.shoppingList)?.value

        XCTAssertEqual(["offline"], crashReporter.values(for: .networkState))
    }

    func testTheFirstScreenChangeQueriesTheDataShape() async {
        await context.onScreen(.shoppingList)?.value

        XCTAssertEqual(1, dataShape.activeCalls)
        XCTAssertEqual(["11-20"], crashReporter.values(for: .itemCountBucket))
        XCTAssertEqual(["1"], crashReporter.values(for: .syncQueueDepth))
    }

    func testScreenChangesInsideTheWindowDoNotQueryAgain() async {
        await context.onScreen(.shoppingList)?.value
        clock.now += 5_000
        await context.onScreen(.shoppingItems)?.value
        clock.now += 5_000
        await context.onScreen(.shoppingList)?.value

        XCTAssertEqual(1, dataShape.activeCalls)
        XCTAssertEqual(1, dataShape.pendingItemCalls)
        XCTAssertEqual(1, dataShape.pendingListCalls)
    }

    func testAScreenChangeAfterTheWindowQueriesAgain() async {
        await context.onScreen(.shoppingList)?.value
        clock.now += 30_000
        await context.onScreen(.shoppingItems)?.value

        XCTAssertEqual(2, dataShape.activeCalls)
    }

    func testThePerScreenKeysAreStillSetOnEveryChange() async {
        // Only the database reads are throttled; where the user is and whether they are online
        // are cheap and must stay current.
        await context.onScreen(.shoppingList)?.value
        await context.onScreen(.shoppingItems)?.value

        XCTAssertEqual(["shopping_list", "shopping_items"], crashReporter.values(for: .lastScreen))
        XCTAssertEqual(2, crashReporter.values(for: .networkState).count)
    }
}
