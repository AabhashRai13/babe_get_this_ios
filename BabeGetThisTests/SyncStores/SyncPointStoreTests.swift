import XCTest
@testable import BabeGetThis

// Real UserDefaults: a sync point that does not survive the store being
// recreated would make every cold start a full pull.
final class SyncPointStoreTests: XCTestCase {
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "SyncPointStoreTests-\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func store() -> PrefsSyncPointStore {
        PrefsSyncPointStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    func testAListWithNoMarkReadsAsNil() {
        XCTAssertNil(store().get(listId: "list-1"))
    }

    func testAMarkSurvivesANewInstance() {
        store().set(listId: "list-1", iso: "2026-11-06T10:00:00Z")

        XCTAssertEqual(store().get(listId: "list-1"), "2026-11-06T10:00:00Z")
    }

    func testRemoveDropsOneListsMarkAndLeavesTheOthers() {
        let store = store()
        store.set(listId: "list-1", iso: "2026-11-06T10:00:00Z")
        store.set(listId: "list-2", iso: "2026-11-06T11:00:00Z")

        store.remove(listId: "list-1")

        XCTAssertNil(store.get(listId: "list-1"))
        XCTAssertEqual(store.get(listId: "list-2"), "2026-11-06T11:00:00Z")
    }

    func testClearDropsEveryMark() {
        let store = store()
        store.set(listId: "list-1", iso: "2026-11-06T10:00:00Z")
        store.set(listId: "list-2", iso: "2026-11-06T11:00:00Z")

        store.clear()

        XCTAssertNil(store.get(listId: "list-1"))
        XCTAssertNil(store.get(listId: "list-2"))
    }
}
