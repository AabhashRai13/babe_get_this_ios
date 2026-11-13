import XCTest
@testable import BabeGetThis

/// The lists overview on a real in-memory database (Android ShoppingListViewModel and the
/// ShoppingListComponentsTest card/tab/greeting cases that are logic rather than layout).
@MainActor
final class ListsViewModelTests: XCTestCase {
    private var db: AppDatabase!
    private var observation: Task<Void, Never>?

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
    }

    override func tearDown() async throws {
        observation?.cancel()
        observation = nil
    }

    // MARK: - Helpers

    private func repository(_ auth: AuthStateManager) -> ShoppingListRepository {
        ShoppingListRepository(
            listDao: db.lists, itemDao: db.items, categoryDao: db.categories, authStateManager: auth,
            syncKicker: CountingSyncKicker(), safeCall: SafeCall(reporter: SilentAppErrorReporter()))
    }

    /// A view model following the database, as the screen's `.task` runs it.
    private func observedViewModel(_ auth: AuthStateManager = authStateFor(nil)) -> ListsViewModel {
        let vm = ListsViewModel(repository: repository(auth), authState: auth)
        observation = Task { await vm.observeLists() }
        return vm
    }

    private func seedList(_ id: String, createdAt: Int64 = TestData.t0, accountId: String? = nil,
                          items: Int = 0, picked: Int = 0) async throws {
        try await db.lists.insertList(TestData.listEntity(id: id, name: id, createdAt: createdAt).with {
            $0.accountId = accountId
        })
        for index in 0..<items {
            try await db.items.insertItems([
                TestData.itemEntity(id: "\(id)-\(index)", listId: id, isPickedUp: index < picked),
            ])
        }
    }

    private func waitUntil(timeout: TimeInterval = 3, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out", line: line) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func list(_ id: String, total: Int, picked: Int, createdAt: Date = .now) -> ShoppingListSummary {
        .init(id: id, name: id, totalItems: total, pickedUpItems: picked, createdAt: createdAt)
    }

    // MARK: - Lists from the database (HOME-03)

    func testListsComeFromDatabaseNewestCreatedFirst() async throws {
        try await seedList("old", createdAt: TestData.t0)
        try await seedList("new", createdAt: TestData.t0 + TestData.day)
        let vm = observedViewModel()

        try await waitUntil { vm.lists.count == 2 }
        XCTAssertEqual(vm.lists.map(\.id), ["new", "old"])
    }

    func testListsUpdateLiveWhenTheDatabaseChanges() async throws {
        let vm = observedViewModel()
        try await waitUntil { vm.hasNoLists }

        try await seedList("groceries", items: 2, picked: 1)

        try await waitUntil { vm.lists.first?.totalItems == 2 }
        XCTAssertEqual(vm.lists.first?.pickedUpItems, 1)
    }

    func testSignedInUserSeesOnlyTheirAccountLists() async throws {
        try await seedList("guest")
        try await seedList("mine", accountId: "u1")
        try await seedList("theirs", accountId: "u2")
        let vm = observedViewModel(authStateFor("u1"))

        try await waitUntil { !vm.lists.isEmpty }
        XCTAssertEqual(vm.lists.map(\.id), ["mine"])
    }

    func testSplitsActiveAndCompleted() async throws {
        try await seedList("empty")
        try await seedList("partial", items: 3, picked: 1)
        try await seedList("done", items: 2, picked: 2)
        let vm = observedViewModel()

        try await waitUntil { vm.lists.count == 3 }
        XCTAssertEqual(Set(vm.activeLists.map(\.id)), ["empty", "partial"])
        XCTAssertEqual(vm.completedLists.map(\.id), ["done"])
    }

    func testCreateListGoesThroughTheRepositoryAndSwitchesToActive() async throws {
        let vm = observedViewModel()
        vm.selectedTab = .completed

        let id = await vm.createList(named: "  Groceries \n")

        XCTAssertNotNil(id)
        XCTAssertEqual(vm.selectedTab, .active)
        try await waitUntil { vm.lists.count == 1 }
        XCTAssertEqual(vm.lists.first?.name, "Groceries")
        XCTAssertEqual(vm.lists.first?.id, id)
    }

    func testCreateListRejectsBlankName() async throws {
        let vm = observedViewModel()

        let id = await vm.createList(named: "   ")

        XCTAssertNil(id)
        XCTAssertEqual(vm.errorMessage, "List name can't be empty.")
        let stored = try await db.lists.listsWithItemCount(accountId: nil)
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - Tabs, panes and date buckets (HOME-05, HOME-08)

    func testPaneFollowsTab() {
        let vm = ListsViewModel(lists: [list("a", total: 1, picked: 0), list("b", total: 1, picked: 1)])
        XCTAssertEqual(vm.pane(for: .active).sections.flatMap(\.lists).map(\.id), ["a"])
        XCTAssertEqual(vm.pane(for: .completed).sections.flatMap(\.lists).map(\.id), ["b"])
    }

    func testPaneGroupsListsByCreatedDateInOrder() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2024, month: 6, day: 25, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let lastYear = calendar.date(byAdding: .year, value: -1, to: now)!
        let vm = ListsViewModel(lists: [
            list("t1", total: 1, picked: 0, createdAt: now),
            list("t2", total: 1, picked: 0, createdAt: now.addingTimeInterval(-60)),
            list("y", total: 1, picked: 0, createdAt: yesterday),
            list("o", total: 1, picked: 0, createdAt: lastYear),
        ])

        let sections = vm.pane(for: .active, now: now, calendar: calendar).sections

        XCTAssertEqual(sections.map(\.period), [.today, .yesterday, .older])
        XCTAssertEqual(sections.map { $0.lists.map(\.id) }, [["t1", "t2"], ["y"], ["o"]])
    }

    func testEmptyTabMessages() {
        let vm = ListsViewModel(lists: [list("done", total: 1, picked: 1)])
        XCTAssertTrue(vm.pane(for: .active).isEmpty)
        XCTAssertEqual(vm.pane(for: .active).emptyMessage, "All done! All your lists are completed.")
        XCTAssertEqual(vm.pane(for: .completed).emptyMessage, "No completed lists yet")
    }

    func testTabIconsAreOutlinedWhenInactiveAndFilledWhenActive() {
        XCTAssertEqual(ListsViewModel.Tab.active.systemImage(selected: false), "cart")
        XCTAssertEqual(ListsViewModel.Tab.active.systemImage(selected: true), "cart.fill")
        XCTAssertEqual(ListsViewModel.Tab.completed.systemImage(selected: false), "checkmark.circle")
        XCTAssertEqual(ListsViewModel.Tab.completed.systemImage(selected: true), "checkmark.circle.fill")
        XCTAssertEqual(ListsViewModel.Tab.allCases.map(\.title), ["Active", "Completed"])
    }

    // MARK: - Greeting (HOME-18)

    func testGreetingShowsOnActiveTabOnly() {
        let vm = ListsViewModel(lists: [list("a", total: 2, picked: 0), list("done", total: 1, picked: 1)])
        XCTAssertTrue(vm.pane(for: .active).showsGreeting)
        XCTAssertFalse(vm.pane(for: .completed).showsGreeting)
    }

    func testGreetingSummaryCountsOnlyActiveLists() {
        let vm = ListsViewModel(lists: [list("a", total: 7, picked: 3), list("b", total: 5, picked: 0),
                                        list("done", total: 2, picked: 2)])
        XCTAssertEqual(vm.greetingSummary, "2 lists · 9 items to get")
    }

    func testGreetingUsesTheSignedInUsersFirstName() {
        let tokens = InMemoryTokenStore()
        tokens.saveUserId("u1")
        tokens.saveToken("t")
        tokens.saveUserName("Aabhash Rai")
        let auth = AuthStateManager(tokenStore: tokens)
        auth.initialize()
        let vm = ListsViewModel(repository: repository(auth), authState: auth)

        XCTAssertEqual(vm.greetingTitle(hour: 14), "Good afternoon, Aabhash")
    }

    func testGreetingStaysImpersonalForGuests() {
        let auth = authStateFor(nil)
        let vm = ListsViewModel(repository: repository(auth), authState: auth)
        XCTAssertEqual(vm.greetingTitle(hour: 9), "Good morning")
    }

    // MARK: - List card (HOME-17)

    func testCompletedCardShowsCheckAndItemCount() {
        let card = ListCardContent(list: list("Groceries", total: 5, picked: 5), isCompletedTab: true)
        XCTAssertEqual(card.systemImage, "checkmark")
        XCTAssertEqual(card.subtitle, "5 items")
        XCTAssertTrue(card.isNameMuted)

        let single = ListCardContent(list: list("One", total: 1, picked: 1), isCompletedTab: true)
        XCTAssertEqual(single.subtitle, "1 item")
    }

    func testActiveCardShowsCartAndProgress() {
        let card = ListCardContent(list: list("Groceries", total: 5, picked: 3), isCompletedTab: false)
        XCTAssertEqual(card.systemImage, "cart")
        XCTAssertEqual(card.subtitle, "3/5 items")
        XCTAssertFalse(card.isNameMuted)
        XCTAssertEqual(ListCardContent(list: list("x", total: 5, picked: 0), isCompletedTab: false).subtitle, "0/5 items")
        XCTAssertEqual(ListCardContent(list: list("x", total: 1, picked: 0), isCompletedTab: false).subtitle, "0/1 item")
    }

    func testEmptyListSubtitleIsNoItemsYet() {
        let empty = list("Groceries", total: 0, picked: 0)
        XCTAssertEqual(ListCardContent(list: empty, isCompletedTab: false).subtitle, "No items yet")
        XCTAssertEqual(ListCardContent(list: empty, isCompletedTab: true).subtitle, "No items yet")
    }
}

final class GreetingTests: XCTestCase {
    func testPrefixByHour() {
        XCTAssertEqual(Greeting.prefix(hour: 0), "Good morning")
        XCTAssertEqual(Greeting.prefix(hour: 11), "Good morning")
        XCTAssertEqual(Greeting.prefix(hour: 12), "Good afternoon")
        XCTAssertEqual(Greeting.prefix(hour: 16), "Good afternoon")
        XCTAssertEqual(Greeting.prefix(hour: 17), "Good evening")
    }

    func testTitleUsesFirstNameOnly() {
        XCTAssertEqual(Greeting.title(hour: 14, userName: "Aabhash Rai"), "Good afternoon, Aabhash")
        XCTAssertEqual(Greeting.title(hour: 14, userName: "  "), "Good afternoon")
        XCTAssertEqual(Greeting.title(hour: 14, userName: nil), "Good afternoon")
    }

    func testSummaryPlurals() {
        XCTAssertEqual(Greeting.summary(listCount: 1, itemsToGet: 1), "1 list · 1 item to get")
        XCTAssertEqual(Greeting.summary(listCount: 3, itemsToGet: 14), "3 lists · 14 items to get")
        XCTAssertEqual(Greeting.summary(listCount: 0, itemsToGet: 0), "0 lists · nothing to pick up yet")
        XCTAssertEqual(Greeting.summary(listCount: 1, itemsToGet: 0), "1 list · nothing to pick up yet")
        XCTAssertEqual(Greeting.summary(listCount: 3, itemsToGet: 1), "3 lists · 1 item to get")
    }

    func testProgressPluralisedOnTotal() {
        XCTAssertEqual(Greeting.progress(picked: 0, total: 1), "0/1 item")
        XCTAssertEqual(Greeting.progress(picked: 3, total: 7), "3/7 items")
    }
}
