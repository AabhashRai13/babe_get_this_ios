import XCTest
@testable import BabeGetThis

/// The 5 ListJustCompleted cases of Android's ShoppingItemsViewModelTest (DET-13).
@MainActor
final class ListCompletedEventTests: XCTestCase {
    private var source: FakeListDetailItemsSource!
    private var haptics: RecordingHapticPlayer!
    private var observation: Task<Void, Never>?

    override func setUp() async throws {
        source = FakeListDetailItemsSource()
        haptics = RecordingHapticPlayer()
    }

    override func tearDown() async throws {
        observation?.cancel()
        observation = nil
    }

    private func buildViewModel() -> ListDetailViewModel {
        let vm = ListDetailViewModel(listId: "L1", source: source, haptics: haptics)
        observation = Task { await vm.observeItems() }
        return vm
    }

    private func emit(_ items: [StoredShoppingItem], to vm: ListDetailViewModel,
                      file: StaticString = #filePath, line: UInt = #line) async {
        source.send(items)
        await listDetailEventually("items never reached the view model", file: file, line: line) {
            vm.storedItems == items
        }
    }

    private func item(_ id: String, isPickedUp: Bool = false) -> StoredShoppingItem {
        TestData.storedItem(id, isPickedUp: isPickedUp)
    }

    func testEmitsWhenLastUncheckedItemIsTickedOff() async {
        let vm = buildViewModel()
        await emit([item("1"), item("2")], to: vm)
        XCTAssertEqual(vm.completionCount, 0)

        await emit([item("1", isPickedUp: true), item("2", isPickedUp: true)], to: vm)
        XCTAssertEqual(vm.completionCount, 1)
        XCTAssertEqual(haptics.played, [.success])
    }

    func testDoesNotEmitOnInitialLoadOfAlreadyCompleteList() async {
        let complete = [item("1", isPickedUp: true), item("2", isPickedUp: true)]
        source.send(complete)

        let vm = buildViewModel()
        await listDetailEventually { vm.storedItems == complete }

        XCTAssertTrue(vm.isAllDone)
        XCTAssertEqual(vm.completionCount, 0)
        XCTAssertTrue(haptics.played.isEmpty)
    }

    func testEmitsOnTheSecondCompletionWhenUncheckThenRecomplete() async {
        let vm = buildViewModel()
        await emit([item("1")], to: vm)
        await emit([item("1", isPickedUp: true)], to: vm)
        XCTAssertEqual(vm.completionCount, 1)

        await emit([item("1", isPickedUp: false)], to: vm)
        await emit([item("1", isPickedUp: true)], to: vm)
        XCTAssertEqual(vm.completionCount, 2)
        XCTAssertEqual(haptics.played, [.success, .success])
    }

    // Nine of ten ticked and the tenth deleted: the trip is done, so the list is complete.
    func testDeletingTheLastUntickedItemCompletesTheList() async {
        let vm = buildViewModel()
        await emit([item("1", isPickedUp: true), item("2")], to: vm)
        await emit([item("1", isPickedUp: true)], to: vm)

        XCTAssertEqual(vm.completionCount, 1)
        XCTAssertEqual(haptics.played, [.success])
    }

    func testEmptyListNeverTriggersCompletion() async {
        let vm = buildViewModel()
        await emit([], to: vm)
        await emit([], to: vm)

        XCTAssertFalse(vm.isAllDone)
        XCTAssertEqual(vm.completionCount, 0)
        XCTAssertTrue(haptics.played.isEmpty)
    }
}
