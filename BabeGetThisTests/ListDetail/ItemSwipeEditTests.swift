import SwiftUI
import XCTest
@testable import BabeGetThis

/// An invalid edit writes nothing. The Android `onEdit` ports are in `ShoppingItemsViewModelTests`.
@MainActor
final class ItemEditTests: XCTestCase {
    func testEditWithAnInvalidDraftWritesNothing() async {
        let source = FakeListDetailItemsSource()
        let vm = ListDetailViewModel(listId: "L1", source: source, haptics: RecordingHapticPlayer())
        let observation = Task { await vm.observeItems() }
        defer { observation.cancel() }
        source.send([TestData.storedItem("a")])
        await listDetailEventually { vm.items.count == 1 }

        var draft = ItemDraft(editing: vm.items[0])
        draft.quantity = "  "
        let saved = await vm.edit("a", with: draft)
        XCTAssertFalse(saved)
        XCTAssertTrue(source.updated.isEmpty)
    }
}

/// Swipe right ticks or unticks, swipe left deletes, a tap opens the editor.
@MainActor
final class ItemCardTests: XCTestCase {
    func testSwipeRightTogglesPickedUp() async {
        let source = FakeListDetailItemsSource()
        let haptics = RecordingHapticPlayer()
        let vm = ListDetailViewModel(listId: "L1", source: source, haptics: haptics)
        let observation = Task { await vm.observeItems() }
        defer { observation.cancel() }
        source.send([TestData.storedItem("a")])
        await listDetailEventually { vm.items.count == 1 }

        // The same construction the screen's itemRow uses.
        let item = vm.items[0]
        let controller = ItemCardActions.forItem(item, in: vm, onEdit: {}, onDelete: {})
            .card(for: item, haptics: haptics) { EmptyView() }
            .controller
        XCTAssertTrue(controller.isAllowed(.towardTrailing))

        // A drag past the 56pt threshold, released slowly.
        controller.end(translation: 80, velocity: 0)
        await listDetailEventually { source.toggled.count == 1 }
        XCTAssertEqual(source.toggled.first?.itemId, "a")
        XCTAssertEqual(source.toggled.first?.isPickedUp, true)
    }

    func testShortSwipeRightDoesNothing() {
        var toggles = 0
        let actions = ItemCardActions(onToggle: { toggles += 1 }, onEdit: {}, onDelete: {})
        actions.card(for: ShoppingItem(id: "a", name: "Milk", quantity: "1"), haptics: RecordingHapticPlayer()) { EmptyView() }
            .controller.end(translation: 30, velocity: 0)
        XCTAssertEqual(toggles, 0)
    }

    func testSwipeLeftDeletesWithoutToggling() {
        var toggles = 0
        var deletes = 0
        let actions = ItemCardActions(onToggle: { toggles += 1 }, onEdit: {}, onDelete: { deletes += 1 })
        actions.card(for: ShoppingItem(id: "a", name: "Milk", quantity: "1"), haptics: RecordingHapticPlayer()) { EmptyView() }
            .controller.end(translation: -80, velocity: 0)
        XCTAssertEqual(deletes, 1)
        XCTAssertEqual(toggles, 0)
    }

    func testTogglingAPickedUpItemUnticksIt() async {
        let source = FakeListDetailItemsSource()
        let vm = ListDetailViewModel(listId: "L1", source: source, haptics: RecordingHapticPlayer())
        let observation = Task { await vm.observeItems() }
        defer { observation.cancel() }
        source.send([TestData.storedItem("a", isPickedUp: true)])
        await listDetailEventually { vm.items.count == 1 }

        await vm.toggle("a")
        XCTAssertEqual(source.toggled.first?.isPickedUp, false)
    }
}

/// Port of the counter cases of Android's `AddItemDialog`: `n/limit` shows once the field is at its limit.
final class ItemDraftTests: XCTestCase {
    func testCounterShowsAtTheLimit() {
        var draft = ItemDraft()
        draft.name = String(repeating: "a", count: ItemDraft.nameLimit - 1)
        draft.note = String(repeating: "b", count: ItemDraft.noteLimit)
        draft.shop = String(repeating: "c", count: ItemDraft.shopLimit)
        XCTAssertNil(draft.nameCounter)
        XCTAssertEqual(draft.noteCounter, "80/80")
        XCTAssertEqual(draft.shopCounter, "40/40")

        draft.name += "a"
        XCTAssertEqual(draft.nameCounter, "60/60")
    }

    func testCounterIsHiddenBelowTheLimit() {
        var draft = ItemDraft()
        XCTAssertNil(draft.nameCounter)
        XCTAssertNil(draft.noteCounter)
        XCTAssertNil(draft.shopCounter)
        draft.note = "short"
        XCTAssertNil(draft.noteCounter)
    }
}
