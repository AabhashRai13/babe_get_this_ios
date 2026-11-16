import XCTest
@testable import BabeGetThis

/// The six telemetry cases of Android `ShoppingListViewModelTest` (TEL-04), against
/// `ListsViewModel` with the app's own adapter (`TrackingListAnalytics`) reporting to a
/// recording analytics and to real markers in a throwaway UserDefaults suite.
///
/// Android's relaxed MockK markers answer `firstTime()` with false ("already fired"); a case here
/// that relies on that marks the activation first, so its event list can be checked exactly.
@MainActor
final class ShoppingListViewModelTelemetryTests: XCTestCase {
    private var analytics: RecordingAnalytics!
    private var scratch: ScratchMarkers!
    private var repository: VoiceListRepository!

    override func setUp() async throws {
        try await super.setUp()
        analytics = RecordingAnalytics()
        scratch = ScratchMarkers()
        repository = VoiceListRepository()
    }

    override func tearDown() async throws {
        scratch.remove()
        try await super.tearDown()
    }

    private func viewModel(joiner: (any ListJoining)? = nil) -> ListsViewModel {
        let auth = authStateFor(nil)
        return ListsViewModel(
            repository: repository, authState: auth, shareJoiner: joiner,
            analytics: TrackingListAnalytics(analytics: analytics, markers: scratch.markers, authState: auth))
    }

    // MARK: - Voice-created lists

    func testAVoiceCreatedListReportsOneAddAndOneAutoCategoryPerDraft() async {
        scratch.markers.mark(.firstItemAdded, scope: nil)
        let vm = viewModel()

        _ = await vm.createListWithVoice([
            TestData.draft(name: "Milk", category: "cat-dairy-eggs"),
            TestData.draft(name: "Something odd", category: nil),
        ])

        // Exact, so nothing else (a name, say) rides along.
        XCTAssertEqual(analytics.events, [
            .itemAdded(inputMethod: .voice, categorySource: .auto),
            .categoryAutoAssigned(categoryId: "cat-dairy-eggs"),
            .itemAdded(inputMethod: .voice, categorySource: .none),
            .categoryAutoAssigned(categoryId: nil),
        ])
    }

    func testActivationIsReportedOnceEvenThoughAVoiceListAddsManyItems() async {
        let vm = viewModel()

        _ = await vm.createListWithVoice([TestData.draft(name: "Milk"), TestData.draft(name: "Eggs")])

        // Three spoken items are one activation, not three.
        XCTAssertEqual(analytics.count(.firstItemAdded(.voice)), 1)
    }

    func testAFailedVoiceListReportsNothing() async {
        repository.result = .failure(.database())
        let vm = viewModel()

        _ = await vm.createListWithVoice([TestData.draft(name: "Milk")])

        XCTAssertEqual(analytics.events, [])
    }

    // MARK: - Joining a shared list

    func testAJoinAttemptIsReportedBeforeTheOutcomeIsKnown() async {
        let joiner = TelemetryJoiner(result: .success("L1"))
        let analytics = self.analytics!
        joiner.onJoin = { [weak joiner] in joiner?.eventsAtJoin = analytics.events }
        let vm = viewModel(joiner: joiner)

        await vm.joinList(code: "ABC234")

        // Counted even for joins that never return, or the conversion rate flatters itself.
        XCTAssertEqual(joiner.eventsAtJoin, [.shareJoinAttempted])
        XCTAssertEqual(analytics.events, [.shareJoinAttempted, .shareJoinSucceeded])
    }

    func testASuccessfulJoinRecordsThatThisDeviceIsTheJoiners() async {
        let vm = viewModel(joiner: TelemetryJoiner(result: .success("L1")))

        await vm.joinList(code: "ABC234")

        // Read back by the list detail screen: after sync nothing else tells joiner from owner.
        XCTAssertTrue(scratch.markers.has(.joinedList, scope: "L1"))
    }

    func testABadCodeReportsTheReasonAndNeverTheCode() async {
        let vm = viewModel(joiner: TelemetryJoiner(result: .failure(.notFound("nope"))))

        await vm.joinList(code: "XXXXXX")

        XCTAssertEqual(analytics.events, [.shareJoinAttempted, .shareJoinFailed(.invalidCode)])
        XCTAssertEqual(scratch.scopes(of: .joinedList), [])
    }
}

// MARK: - Fakes

/// Only `createListWithItems` matters here; the rest answer like an empty, healthy repository.
private final class VoiceListRepository: ListsRepositoryProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<String, AppError> = .success("L1")

    var result: Result<String, AppError> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    func allLists() -> AsyncThrowingStream<[ShoppingList], any Error> {
        AsyncThrowingStream { $0.yield([]) }
    }

    func createList(name: String) async throws -> Result<String, AppError> { .success("new-id") }

    func createListWithItems(name: String, drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        result
    }

    func updateListName(listId: String, newName: String) async throws -> Result<Void, AppError> { .success(()) }

    func deleteListAndCaptureItems(listId: String) async throws -> Result<[ShoppingItemRecord], AppError> {
        .success([])
    }

    func restoreListWithItems(list: ShoppingList, items: [ShoppingItemRecord]) async throws -> Result<Void, AppError> {
        .success(())
    }
}

/// Answers `result`, running `onJoin` first so a test can see what was tracked before it returned.
private final class TelemetryJoiner: ListJoining, @unchecked Sendable {
    private let result: Result<String, AppError>
    var onJoin: (@MainActor () -> Void)?
    var eventsAtJoin: [AnalyticsEvent]?

    init(result: Result<String, AppError>) {
        self.result = result
    }

    func join(code: String) async throws -> Result<String, AppError> {
        if let onJoin { await onJoin() }
        return result
    }
}
