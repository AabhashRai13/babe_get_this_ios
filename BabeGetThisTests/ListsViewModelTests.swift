import XCTest
@testable import BabeGetThis

@MainActor
final class ListsViewModelTests: XCTestCase {
    private func list(_ id: String, total: Int, picked: Int, minutesAgo: Double = 0) -> ShoppingListSummary {
        .init(id: id, name: id, totalItems: total, pickedUpItems: picked,
              updatedAt: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60))
    }

    func testSplitsActiveAndCompleted() {
        let vm = ListsViewModel(lists: [
            list("empty", total: 0, picked: 0),
            list("partial", total: 3, picked: 1),
            list("done", total: 2, picked: 2),
        ])
        XCTAssertEqual(Set(vm.activeLists.map(\.id)), ["empty", "partial"])
        XCTAssertEqual(vm.completedLists.map(\.id), ["done"])
    }

    func testListsSortedNewestFirst() {
        let vm = ListsViewModel(lists: [list("old", total: 1, picked: 0, minutesAgo: 10),
                                        list("new", total: 1, picked: 0)])
        XCTAssertEqual(vm.activeLists.map(\.id), ["new", "old"])
    }

    func testVisibleListsFollowSelectedTab() {
        let vm = ListsViewModel(lists: [list("a", total: 1, picked: 0), list("b", total: 1, picked: 1)])
        XCTAssertEqual(vm.visibleLists.map(\.id), ["a"])
        vm.selectedTab = .completed
        XCTAssertEqual(vm.visibleLists.map(\.id), ["b"])
    }

    func testCreateListTrimsNameAndSwitchesToActive() {
        let vm = ListsViewModel()
        vm.selectedTab = .completed
        let created = vm.createList(named: "  Groceries \n", id: "x")
        XCTAssertEqual(created?.name, "Groceries")
        XCTAssertEqual(vm.lists.map(\.id), ["x"])
        XCTAssertEqual(vm.selectedTab, .active)
    }

    func testCreateListRejectsBlankName() {
        let vm = ListsViewModel()
        XCTAssertNil(vm.createList(named: "   "))
        XCTAssertTrue(vm.lists.isEmpty)
    }

    func testGreetingSummaryCountsOnlyActiveLists() {
        let vm = ListsViewModel(lists: [list("a", total: 7, picked: 3), list("b", total: 5, picked: 0),
                                        list("done", total: 2, picked: 2)])
        XCTAssertEqual(vm.greetingSummary, "2 lists · 9 items to get")
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
    }

    func testProgressPluralisedOnTotal() {
        XCTAssertEqual(Greeting.progress(picked: 0, total: 1), "0/1 item")
        XCTAssertEqual(Greeting.progress(picked: 3, total: 7), "3/7 items")
    }
}
