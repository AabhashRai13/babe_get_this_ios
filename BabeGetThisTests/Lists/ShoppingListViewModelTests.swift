import XCTest
@testable import BabeGetThis

/// Port of Android `ShoppingListViewModelTest` against `ListsViewModel`, minus the six
/// telemetry cases (iOS v1 has no analytics events yet). The repository and the share
/// repository are fakes that fail on demand, like the Android MockK mocks.
///
/// Name mapping: `setSelectedTab` is `selectedTab`, the create dialog is `isNamingList`,
/// the edit dialog is `renamingList`, `navigateToList` is `openListRequest`, `errorMessage`
/// and `undoDeleteEvent` are `errorMessage` and `undoMessage`.
@MainActor
final class ShoppingListViewModelTests: XCTestCase {
    private var repository: FakeListsRepository!
    private var observation: Task<Void, Never>?
    private let now = Int64(Date().timeIntervalSince1970 * 1000)
    private let day: Int64 = 24 * 60 * 60 * 1000

    override func setUp() async throws {
        repository = FakeListsRepository()
    }

    override func tearDown() async throws {
        observation?.cancel()
        observation = nil
    }

    // MARK: - Helpers

    /// A view model following the repository, as the screen's `.task` runs it. Android's
    /// `viewModel()` subscribes to the state flows for the same reason.
    private func viewModel(
        auth: AuthStateManager = authStateFor(nil),
        joiner: FakeListJoiner? = nil,
        ownership: FakeListOwnershipStore? = nil
    ) -> ListsViewModel {
        let vm = ListsViewModel(repository: repository, authState: auth, shareJoiner: joiner, ownership: ownership)
        observation = Task { await vm.observeLists() }
        return vm
    }

    // Timestamps relative to the real clock: the view model buckets by "now", so relative
    // offsets keep the assertions right on any calendar day.
    private func list(_ id: String, name: String? = nil, createdAt: Int64? = nil,
                      itemCount: Int = 0, completedItemCount: Int = 0) -> ShoppingList {
        ShoppingList(id: id, name: name ?? "List \(id)", createdAt: createdAt ?? now, updatedAt: createdAt ?? now,
                     itemCount: itemCount, completedItemCount: completedItemCount)
    }

    /// Emits `lists` from the repository and waits until the view model shows them.
    private func show(_ lists: [ShoppingList], in vm: ListsViewModel, line: UInt = #line) async throws {
        repository.emit(lists)
        try await waitUntil(line: line) { vm.lists.map(\.id) == lists.map(\.id) }
    }

    private func waitUntil(timeout: TimeInterval = 3, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out", line: line) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func ids(_ pane: ListsViewModel.Pane) -> [String] {
        pane.sections.flatMap(\.lists).map(\.id)
    }

    // MARK: - 2.9 derived state

    func testStartsOnTheActiveTab() {
        XCTAssertEqual(viewModel().selectedTab, .active)
    }

    func testSelectedTabDrivesState() {
        let vm = viewModel()

        vm.selectedTab = .completed

        XCTAssertEqual(vm.selectedTab, .completed)
        XCTAssertFalse(vm.isActiveTab)
    }

    func testStateSplitsActiveFromCompleted() async throws {
        let vm = viewModel()
        try await show([
            list("a", itemCount: 2, completedItemCount: 1), // active
            list("b", itemCount: 2, completedItemCount: 2), // completed
            list("c"), // empty → active
        ], in: vm)

        XCTAssertEqual(vm.activeLists.map(\.id), ["a", "c"])
        XCTAssertEqual(vm.completedLists.map(\.id), ["b"])
    }

    func testActiveItemsToGetSumsOutstandingItemsAcrossActiveListsOnly() async throws {
        let vm = viewModel()
        try await show([
            list("a", itemCount: 5, completedItemCount: 2), // 3 outstanding
            list("b", itemCount: 4, completedItemCount: 1), // 3 outstanding
            list("c", itemCount: 2, completedItemCount: 2), // completed, excluded
        ], in: vm)

        XCTAssertEqual(vm.activeItemsToGet, 6)
    }

    func testActiveItemsToGetIsZeroWithNoLists() {
        XCTAssertEqual(viewModel().activeItemsToGet, 0)
    }

    func testHasNoListsReflectsBothTabsBeingEmpty() async throws {
        let vm = viewModel()
        XCTAssertTrue(vm.hasNoLists)

        try await show([list("a")], in: vm)

        XCTAssertFalse(vm.hasNoLists)
    }

    func testGroupingPreservesTimePeriodOrder() async throws {
        let vm = viewModel()
        // Emitted newest first, the order the repository returns.
        try await show([
            list("today", createdAt: now),
            list("yesterday", createdAt: now - day),
            list("older", createdAt: now - 90 * day),
        ], in: vm)

        let periods = vm.pane(for: .active).sections.map(\.period)

        XCTAssertEqual(periods, [.today, .yesterday, .older])
    }

    func testGroupingBucketsSeveralListsUnderOnePeriod() async throws {
        let vm = viewModel()
        try await show([list("a"), list("b")], in: vm)

        let today = try XCTUnwrap(vm.pane(for: .active).sections.first { $0.period == .today })

        XCTAssertEqual(today.lists.map(\.id), ["a", "b"])
    }

    // Both tabs are built every time so the outgoing pane keeps its own data while it slides away.
    func testBothTabsAreGroupedRegardlessOfSelection() async throws {
        let vm = viewModel()
        try await show([
            list("a", itemCount: 1),
            list("b", itemCount: 1, completedItemCount: 1),
        ], in: vm)

        XCTAssertEqual(ids(vm.pane(for: .active)), ["a"])
        XCTAssertEqual(ids(vm.pane(for: .completed)), ["b"])
    }

    // MARK: - 2.10 dialogs and events

    func testCreateDialogOpensAndDismisses() {
        let vm = viewModel()

        vm.startCreating()
        vm.pickType()
        XCTAssertTrue(vm.isNamingList)

        vm.isNamingList = false
        XCTAssertFalse(vm.isNamingList)
    }

    func testEditDialogHoldsTheListBeingEdited() async throws {
        let vm = viewModel()
        try await show([list("a")], in: vm)

        vm.startRenaming(id: "a")
        XCTAssertEqual(vm.renamingList?.id, "a")

        vm.cancelRenaming()
        XCTAssertNil(vm.renamingList)
    }

    func testCreateListSuccessNavigatesAndClosesTheDialog() async throws {
        repository.configure { $0.createListResult = .success("new-id") }
        let vm = viewModel()
        vm.pickType()

        await vm.confirmCreate(named: "Groceries")

        XCTAssertEqual(vm.openListRequest?.id, "new-id")
        XCTAssertEqual(vm.openListRequest?.name, "Groceries")
        XCTAssertFalse(vm.isNamingList)
    }

    func testCreateListFailureSurfacesTheErrorAndLeavesTheDialogOpen() async throws {
        repository.configure { $0.createListResult = .failure(.validation("List name can't be empty.")) }
        let vm = viewModel()
        vm.pickType()

        await vm.confirmCreate(named: "")

        XCTAssertEqual(vm.errorMessage, "List name can't be empty.")
        XCTAssertTrue(vm.isNamingList, "dialog must stay open so the user can correct it")
        XCTAssertNil(vm.openListRequest)
    }

    func testEditListSuccessClosesTheEditDialog() async throws {
        repository.configure { $0.updateResult = .success(()) }
        let vm = viewModel()
        try await show([list("a")], in: vm)
        vm.startRenaming(id: "a")

        await vm.renameList(id: "a", to: "New")

        XCTAssertNil(vm.renamingList)
        XCTAssertEqual(repository.snapshot().renames, [FakeListsRepository.Rename(listId: "a", newName: "New")])
    }

    func testEditListFailureSurfacesTheErrorAndKeepsTheDialogOpen() async throws {
        repository.configure { $0.updateResult = .failure(.notFound("That list no longer exists.")) }
        let vm = viewModel()
        try await show([list("a")], in: vm)
        vm.startRenaming(id: "a")
        let target = vm.renamingList

        await vm.renameList(id: "a", to: "New")

        XCTAssertEqual(vm.errorMessage, "That list no longer exists.")
        XCTAssertEqual(vm.renamingList, target)
        XCTAssertNotNil(vm.renamingList)
    }

    func testShowSnackBarEmitsTheMessageVerbatim() {
        let vm = viewModel()

        vm.showSnackBar("Signed out")

        XCTAssertEqual(vm.errorMessage, "Signed out")
    }

    // MARK: - 2.11 undo delete

    func testDeleteListEmitsTheUndoEventNamingTheList() async throws {
        repository.configure { $0.deleteResult = .success([]) }
        let vm = viewModel()
        try await show([list("a", name: "Groceries")], in: vm)

        await vm.deleteList(id: "a")

        XCTAssertEqual(vm.undoMessage, "Groceries deleted")
    }

    func testDeleteListFailureSurfacesTheError() async throws {
        repository.configure { $0.deleteResult = .failure(.database()) }
        let vm = viewModel()
        try await show([list("a")], in: vm)

        await vm.deleteList(id: "a")

        XCTAssertEqual(vm.errorMessage, AppError.database().message)
        XCTAssertNil(vm.undoMessage)
    }

    // Regression: an unknown id used to still emit an undo event, giving the user an Undo
    // button that silently did nothing when tapped.
    func testDeleteListOffersNoUndoWhenTheListWasNeverInState() async throws {
        repository.configure { $0.deleteResult = .success([]) }
        let vm = viewModel()

        await vm.deleteList(id: "ghost")

        XCTAssertNil(vm.undoMessage)
    }

    func testUndoDeleteListRestoresTheListWithItsCapturedItems() async throws {
        let items = [ShoppingItemRecord(id: "i1", listId: "a", name: "Milk", quantity: "1", createdAt: 1, updatedAt: 1)]
        repository.configure { $0.deleteResult = .success(items) }
        let vm = viewModel()
        let target = list("a", name: "Groceries")
        try await show([target], in: vm)

        await vm.deleteList(id: "a")
        await vm.undoDelete()

        let restores = repository.snapshot().restores
        XCTAssertEqual(restores.count, 1)
        XCTAssertEqual(restores.first?.list, target)
        XCTAssertEqual(restores.first?.items, items)
    }

    func testUndoDeleteListWithNothingPendingDoesNothing() async throws {
        let vm = viewModel()

        await vm.undoDelete()

        XCTAssertEqual(repository.snapshot().restores.count, 0)
        XCTAssertNil(vm.errorMessage)
    }

    func testASecondUndoAfterASuccessfulRestoreDoesNothing() async throws {
        let vm = viewModel()
        try await show([list("a")], in: vm)

        await vm.deleteList(id: "a")
        await vm.undoDelete()
        await vm.undoDelete()

        XCTAssertEqual(repository.snapshot().restores.count, 1)
    }

    func testUndoDeleteListSurfacesARestoreFailure() async throws {
        repository.configure { $0.restoreResult = .failure(.database()) }
        let vm = viewModel()
        try await show([list("a")], in: vm)
        await vm.deleteList(id: "a")

        await vm.undoDelete()

        XCTAssertEqual(vm.errorMessage, AppError.database().message)
    }

    // Regression: the pending copy used to be cleared before the restore was attempted, so a
    // failed restore discarded the only copy of the list and "try again" was impossible.
    func testAFailedRestoreKeepsTheCacheSoUndoCanBeRetried() async throws {
        repository.configure { $0.restoreResult = .failure(.database()) }
        let vm = viewModel()
        try await show([list("a")], in: vm)
        await vm.deleteList(id: "a")

        await vm.undoDelete()
        await vm.undoDelete()

        XCTAssertEqual(repository.snapshot().restores.count, 2)
    }

    // Android proves the restore runs on the application scope, not viewModelScope. The
    // iOS equivalent: cancelling the task that called undo (tap Undo, then leave the screen)
    // must not abort the restore.
    func testUndoSurvivesTheCallerBeingCancelled() async throws {
        let vm = viewModel()
        try await show([list("a")], in: vm)
        await vm.deleteList(id: "a")

        let tap = Task { await vm.undoDelete() }
        tap.cancel()
        await tap.value

        XCTAssertEqual(repository.snapshot().restores.count, 1)
    }

    // MARK: - 2.12 voice

    func testCreateListWithVoiceDerivesTheNameFromTheDrafts() async throws {
        let vm = viewModel()
        let drafts = [TestData.draft(name: "Milk"), TestData.draft(name: "Eggs")]

        _ = try await vm.createListWithVoice(drafts)

        let created = repository.snapshot().createdWithItems
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.name, "Milk + 1 more")
        XCTAssertEqual(created.first?.drafts, drafts)
    }

    func testCreateListWithVoiceNavigatesOnSuccess() async throws {
        repository.configure { $0.createWithItemsResult = .success("new-id") }
        let vm = viewModel()

        _ = try await vm.createListWithVoice([TestData.draft(name: "Milk")])

        XCTAssertEqual(vm.openListRequest?.id, "new-id")
        XCTAssertEqual(vm.openListRequest?.name, "Milk")
    }

    func testCreateListWithVoiceReturnsTheResultUnchanged() async throws {
        repository.configure { $0.createWithItemsResult = .success("new-id") }
        let vm = viewModel()

        let result = try await vm.createListWithVoice([TestData.draft(name: "Milk")])

        XCTAssertEqual(result, .success("new-id"))
    }

    // No error and no navigation on failure: the voice sheet renders the failure inline,
    // so a second error surface would double up.
    func testCreateListWithVoiceStaysSilentOnFailure() async throws {
        repository.configure { $0.createWithItemsResult = .failure(.database()) }
        let vm = viewModel()

        let result = try await vm.createListWithVoice([TestData.draft(name: "Milk")])

        XCTAssertEqual(result, .failure(.database()))
        XCTAssertNil(vm.openListRequest)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Join a shared list

    func testJoinClickOpensTheDialogWhenSignedIn() {
        let vm = viewModel(auth: authStateFor("user-1"), joiner: FakeListJoiner())

        vm.startJoining()

        XCTAssertTrue(vm.isJoinDialogPresented)
        XCTAssertFalse(vm.isJoinAuthPromptPresented)
    }

    func testJoinClickPromptsSignInWhenSignedOut() {
        let vm = viewModel(auth: authStateFor(nil), joiner: FakeListJoiner())

        vm.startJoining()

        XCTAssertFalse(vm.isJoinDialogPresented)
        XCTAssertTrue(vm.isJoinAuthPromptPresented)

        vm.dismissJoinAuthPrompt()
        XCTAssertFalse(vm.isJoinAuthPromptPresented)
    }

    func testSuccessfulJoinClosesTheDialog() async throws {
        let joiner = FakeListJoiner(result: .success("list-9"))
        let vm = viewModel(auth: authStateFor("user-1"), joiner: joiner)
        vm.startJoining()

        await vm.joinList(code: "ABC234")

        XCTAssertEqual(joiner.codes, ["ABC234"])
        XCTAssertFalse(vm.isJoinDialogPresented)
        XCTAssertNil(vm.joinError)
        XCTAssertFalse(vm.isJoining)
    }

    func testFailedJoinKeepsTheDialogOpenWithTheErrorInline() async throws {
        let joiner = FakeListJoiner(result: .failure(.notFound("That code didn't match any list.")))
        let vm = viewModel(auth: authStateFor("user-1"), joiner: joiner)
        vm.startJoining()

        await vm.joinList(code: "XXXXXX")

        XCTAssertTrue(vm.isJoinDialogPresented)
        XCTAssertEqual(vm.joinError, "That code didn't match any list.")
        XCTAssertFalse(vm.isJoining)
    }

    func testReopeningTheJoinDialogClearsAStaleError() async throws {
        let joiner = FakeListJoiner(result: .failure(.notFound("nope")))
        let vm = viewModel(auth: authStateFor("user-1"), joiner: joiner)
        vm.startJoining()
        await vm.joinList(code: "XXXXXX")
        vm.dismissJoinDialog()

        vm.startJoining()

        XCTAssertNil(vm.joinError)
        XCTAssertTrue(vm.isJoinDialogPresented)
    }

    // MARK: - Signed out by a lost session, and lists moved into the account (decision 008)

    func testIsSessionExpiredFollowsTheAuthState() {
        let auth = authStateFor("u1")
        let vm = viewModel(auth: auth)
        XCTAssertFalse(vm.isSessionExpired)

        auth.expireSession()
        XCTAssertTrue(vm.isSessionExpired)

        auth.logout()
        XCTAssertFalse(vm.isSessionExpired)
    }

    func testTheAdoptionNoticeShowsTheClaimedCountUntilDismissed() {
        let ownership = FakeListOwnershipStore()
        ownership.setAdoptionNotice(3)
        let vm = viewModel(ownership: ownership)

        XCTAssertEqual(vm.adoptionNotice, 3)

        vm.dismissAdoptionNotice()
        XCTAssertEqual(vm.adoptionNotice, 0)
        XCTAssertEqual(ownership.adoptionNotice, 0)
    }
}

// MARK: - Fakes

/// Programmable `ListsRepositoryProviding`: every result is settable, every call recorded.
private final class FakeListsRepository: ListsRepositoryProviding, @unchecked Sendable {
    struct Rename: Equatable { let listId: String; let newName: String }
    struct Restore { let list: ShoppingList; let items: [ShoppingItemRecord] }
    struct CreatedWithItems { let name: String; let drafts: [ItemDraft] }

    struct State {
        var lists: [ShoppingList] = []
        var createListResult: Result<String, AppError> = .success("new-id")
        var createWithItemsResult: Result<String, AppError> = .success("new-id")
        var updateResult: Result<Void, AppError> = .success(())
        var deleteResult: Result<[ShoppingItemRecord], AppError> = .success([])
        var restoreResult: Result<Void, AppError> = .success(())
        var renames: [Rename] = []
        var restores: [Restore] = []
        var createdWithItems: [CreatedWithItems] = []
    }

    private let lock = NSLock()
    private var state = State()
    private var continuation: AsyncThrowingStream<[ShoppingList], any Error>.Continuation?

    func configure(_ change: (inout State) -> Void) { lock.withLock { change(&state) } }
    func snapshot() -> State { lock.withLock { state } }

    /// The next (and any later) stream starts from the latest emission, so a value emitted
    /// before the view model subscribes is not lost.
    func emit(_ lists: [ShoppingList]) {
        lock.withLock {
            state.lists = lists
            continuation?.yield(lists)
        }
    }

    func allLists() -> AsyncThrowingStream<[ShoppingList], any Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                self.continuation = continuation
                continuation.yield(state.lists)
            }
        }
    }

    func createList(name: String) async throws -> Result<String, AppError> {
        lock.withLock { state.createListResult }
    }

    func createListWithItems(name: String, drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        lock.withLock {
            state.createdWithItems.append(CreatedWithItems(name: name, drafts: drafts))
            return state.createWithItemsResult
        }
    }

    func updateListName(listId: String, newName: String) async throws -> Result<Void, AppError> {
        lock.withLock {
            state.renames.append(Rename(listId: listId, newName: newName))
            return state.updateResult
        }
    }

    func deleteListAndCaptureItems(listId: String) async throws -> Result<[ShoppingItemRecord], AppError> {
        lock.withLock { state.deleteResult }
    }

    func restoreListWithItems(list: ShoppingList, items: [ShoppingItemRecord]) async throws -> Result<Void, AppError> {
        // Like the real repository's safeCall: a cancelled caller aborts the write.
        try Task.checkCancellation()
        return lock.withLock {
            state.restores.append(Restore(list: list, items: items))
            return state.restoreResult
        }
    }
}

private final class FakeListJoiner: ListJoining, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<String, AppError>
    private var joined: [String] = []

    init(result: Result<String, AppError> = .success("list-1")) {
        self.result = result
    }

    var codes: [String] { lock.withLock { joined } }

    func join(code: String) async throws -> Result<String, AppError> {
        lock.withLock { joined.append(code) }
        return result
    }
}
