import XCTest
@testable import BabeGetThis

/// The eleven telemetry cases of Android `ShoppingItemsViewModelTest` (TEL-04). On iOS the list
/// screen's state is split: the item cases run against `ListDetailViewModel` and the two share
/// cases against `ShareLiveViewModel`, both with the app's own adapter (`TrackingListAnalytics`)
/// reporting to a recording analytics and to real markers in a throwaway UserDefaults suite.
///
/// These check the two properties that make the analytics worth having: once-only events fire
/// once, and no user content is ever a parameter. Three more pin activation's scope: per signed-in
/// user, and "anon" after a lost session, as on Android. Android's relaxed MockK markers answer
/// `firstTime()` with false ("already fired"); a case that relies on that marks it first.
@MainActor
final class ShoppingItemsViewModelTelemetryTests: XCTestCase {
    private var analytics: RecordingAnalytics!
    private var scratch: ScratchMarkers!
    private var source: FakeListDetailItemsSource!
    private var observers: [Task<Void, Never>] = []

    override func setUp() async throws {
        try await super.setUp()
        analytics = RecordingAnalytics()
        scratch = ScratchMarkers()
        source = FakeListDetailItemsSource()
    }

    override func tearDown() async throws {
        observers.forEach { $0.cancel() }
        observers = []
        scratch.remove()
        try await super.tearDown()
    }

    private func adapter(auth: AuthStateManager = authStateFor(nil)) -> TrackingListAnalytics {
        TrackingListAnalytics(analytics: analytics, markers: scratch.markers, authState: auth)
    }

    /// Android's `buildViewModel()`: the view model starts collecting straight away.
    private func buildViewModel(auth: AuthStateManager = authStateFor(nil)) -> ListDetailViewModel {
        let vm = ListDetailViewModel(listId: "L1", source: source, analytics: adapter(auth: auth),
                                     haptics: RecordingHapticPlayer())
        observers.append(Task { await vm.observeItems() })
        return vm
    }

    /// `itemsFlow.value = items`, then waits until the view model has applied it.
    private func emit(_ items: [StoredShoppingItem], to vm: ListDetailViewModel,
                      file: StaticString = #filePath, line: UInt = #line) async {
        source.send(items)
        await listDetailEventually("items never reached the view model", file: file, line: line) {
            vm.storedItems == items
        }
    }

    private func item(_ id: String, isPickedUp: Bool = false, categoryId: String? = nil) -> StoredShoppingItem {
        var item = TestData.storedItem(id, isPickedUp: isPickedUp)
        item.categoryId = categoryId
        return item
    }

    private func draft(_ name: String, quantity: String = "1", categoryId: String? = nil) -> ItemDraft {
        var draft = ItemDraft()
        draft.name = name
        draft.quantity = quantity
        draft.categoryId = categoryId
        return draft
    }

    private func shareViewModel() -> ShareLiveViewModel {
        ShareLiveViewModel(listId: "L1", authState: { .authenticated(userId: "u1") },
                           sharer: CodeSharer(code: "ABC123"), analytics: adapter(auth: authStateFor("u1")),
                           reportError: { _ in }, copyToClipboard: { _ in })
    }

    // MARK: - Adding items

    func testAManualAddReportsTheInputMethodAndWhoChoseTheCategory() async {
        scratch.markers.mark(.firstItemAdded, scope: nil)
        let vm = buildViewModel()

        _ = await vm.add(draft("Milk", categoryId: "cat-dairy-eggs"))
        _ = await vm.add(draft("Eggs", quantity: "6"))

        XCTAssertEqual(analytics.events, [
            .itemAdded(inputMethod: .manual, categorySource: .user),
            .itemAdded(inputMethod: .manual, categorySource: .none),
        ])
    }

    func testActivationIsReportedOnTheFirstItemOnly() async {
        let vm = buildViewModel()

        _ = await vm.add(draft("Milk"))
        _ = await vm.add(draft("Eggs", quantity: "6"))

        XCTAssertEqual(analytics.count(.firstItemAdded(.manual)), 1)
    }

    func testActivationIsCountedPerSignedInUser() async {
        scratch.markers.mark(.firstItemAdded, scope: "u1")
        let vm = buildViewModel(auth: authStateFor("u2"))

        _ = await vm.add(draft("Milk"))

        // A second account on the phone still records its own activation.
        XCTAssertEqual(analytics.count(.firstItemAdded(.manual)), 1)
        XCTAssertEqual(Set(scratch.scopes(of: .firstItemAdded)), ["u1", "u2"])
    }

    func testALapsedSessionCountsActivationAsAGuestLikeAndroid() async {
        scratch.markers.mark(.firstItemAdded, scope: "u1")
        let vm = buildViewModel(auth: authStateFor("u1", expired: true))

        _ = await vm.add(draft("Milk"))

        // Android scopes by `AuthState.Authenticated` only, so a lost session is "anon" there too.
        XCTAssertEqual(analytics.count(.firstItemAdded(.manual)), 1)
        XCTAssertEqual(Set(scratch.scopes(of: .firstItemAdded)), ["u1", "anon"])
    }

    func testVoiceItemsReportOneAddAndOneAutoCategoryEach() async {
        scratch.markers.mark(.firstItemAdded, scope: nil)
        let vm = buildViewModel()

        _ = await vm.addItemsWithVoice([
            TestData.draft(name: "Milk", category: "cat-dairy-eggs"),
            TestData.draft(name: "Something odd", category: nil),
        ], using: ItemsAdder(result: .success("L1")))

        XCTAssertEqual(analytics.events, [
            .itemAdded(inputMethod: .voice, categorySource: .auto),
            .categoryAutoAssigned(categoryId: "cat-dairy-eggs"),
            .itemAdded(inputMethod: .voice, categorySource: .none),
            .categoryAutoAssigned(categoryId: nil),
        ])
    }

    // MARK: - Ticking and editing

    func testCheckingAnItemOffIsReportedUncheckingIsNot() async {
        let vm = buildViewModel()
        await emit([item("i1")], to: vm)
        await vm.toggle("i1")
        await emit([item("i1", isPickedUp: true)], to: vm)

        await vm.toggle("i1")

        // Un-checking is a correction; counting it would inflate the shopping activity.
        XCTAssertEqual(source.toggled.map(\.isPickedUp), [true, false])
        XCTAssertEqual(analytics.count(.itemCheckedOff), 1)
    }

    func testChangingACategoryReportsTheCorrectionWithBothTaxonomyIds() async {
        let vm = buildViewModel()
        await emit([item("1", categoryId: "cat-dairy-eggs")], to: vm)

        _ = await vm.edit("1", with: draft("Milk", categoryId: "cat-frozen-foods"))

        XCTAssertEqual(analytics.events, [
            .categoryCorrected(fromCategoryId: "cat-dairy-eggs", toCategoryId: "cat-frozen-foods"),
        ])
    }

    func testAnEditThatLeavesTheCategoryAloneIsNotACorrection() async {
        let vm = buildViewModel()
        await emit([item("1", categoryId: "cat-dairy-eggs")], to: vm)

        // Renaming only. Reporting it would make the taxonomy look far worse than it is.
        let saved = await vm.edit("1", with: draft("Whole milk", categoryId: "cat-dairy-eggs"))

        XCTAssertTrue(saved)
        XCTAssertFalse(analytics.events.contains { $0.kind == .categoryCorrected })
    }

    // MARK: - Sharing

    func testReopeningTheShareDialogDoesNotReportASecondShare() async {
        let vm = shareViewModel()

        // share() hands back the EXISTING code after the first time, so only the marker can tell
        // a new share from a re-open.
        await vm.shareLive()
        vm.dismissShareCode()
        await vm.shareLive()

        XCTAssertEqual(vm.shareCode, "ABC123")
        XCTAssertEqual(analytics.count(.shareCodeCreated), 1)
    }

    func testCopyingTheCodeIsWhatCountsAsSharingIt() async {
        let vm = shareViewModel()
        await vm.shareLive()
        XCTAssertEqual(analytics.count(.shareCodeShared), 0, "showing the code is not sharing it")

        vm.copyCode()

        XCTAssertEqual(analytics.count(.shareCodeShared), 1)
    }

    // MARK: - A joiner's first edit

    func testOnlyTheJoiningDeviceReportsAJoinersFirstEditAndOnlyOnce() async {
        scratch.markers.mark(.joinedList, scope: "L1")
        let vm = buildViewModel()
        await emit([item("i1"), item("i2")], to: vm)

        await vm.toggle("i1")
        await vm.toggle("i2")

        XCTAssertEqual(analytics.count(.sharedListFirstEditByJoiner), 1)
    }

    func testTheOwnersDeviceNeverReportsAJoinersFirstEdit() async {
        // Owner and joiner devices look the same once the list syncs: only the marker written
        // at join time tells them apart.
        let vm = buildViewModel()
        await emit([item("i1")], to: vm)

        await vm.toggle("i1")

        XCTAssertEqual(source.toggled.count, 1)
        XCTAssertEqual(analytics.count(.sharedListFirstEditByJoiner), 0)
    }

    // MARK: - Completing a list

    func testCompletingAListReportsTheTripAndTheFirstOneReportsActivation() async {
        let vm = buildViewModel()
        await emit([item("1"), item("2")], to: vm)
        XCTAssertEqual(analytics.events, [])

        await emit([item("1", isPickedUp: true), item("2", isPickedUp: true)], to: vm)

        XCTAssertEqual(vm.completionCount, 1)
        XCTAssertEqual(analytics.events, [.listCompleted(itemCount: 2), .firstListCompleted(itemCount: 2)])
    }

    func testAFirstCompletedListIsCountedPerSignedInUser() async {
        scratch.markers.mark(.firstListCompleted, scope: "u1")
        let vm = buildViewModel(auth: authStateFor("u2"))
        await emit([item("1")], to: vm)

        await emit([item("1", isPickedUp: true)], to: vm)

        XCTAssertEqual(analytics.events, [.listCompleted(itemCount: 1), .firstListCompleted(itemCount: 1)])
        XCTAssertEqual(Set(scratch.scopes(of: .firstListCompleted)), ["u1", "u2"])
    }
}

// MARK: - Fakes

/// Android `listRepository.addItemsToList`, answering `result`.
private struct ItemsAdder: ListItemsAdding {
    let result: Result<String, AppError>

    func addItemsToList(listId: String, drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        result
    }
}

/// Android `shareRepository.share`: the list's one code, every time.
private struct CodeSharer: ListSharing {
    let code: String

    func share(listId: String) async throws -> Result<String, AppError> { .success(code) }
}
