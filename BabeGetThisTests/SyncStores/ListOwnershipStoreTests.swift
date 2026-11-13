import XCTest
@testable import BabeGetThis

// Everything here exists to survive sign-out eviction and process death, so each
// test reads back through a NEW instance: an in-memory copy that forgets on
// restart would pass a weaker test and fail the user.
final class ListOwnershipStoreTests: XCTestCase {
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "ListOwnershipStoreTests-\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func store() -> PrefsListOwnershipStore {
        PrefsListOwnershipStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    func testTheAdoptionNoticeStartsAtZeroAndIsObservable() async {
        let store = store()
        XCTAssertEqual(store.adoptionNotice, 0)

        var updates = store.adoptionNoticeUpdates().makeAsyncIterator()
        let first = await updates.next()
        XCTAssertEqual(first, 0)

        store.setAdoptionNotice(3)

        XCTAssertEqual(store.adoptionNotice, 3)
        let second = await updates.next()
        XCTAssertEqual(second, 3)
    }

    func testTheAdoptionNoticeSurvivesANewInstance() {
        store().setAdoptionNotice(2)

        XCTAssertEqual(store().adoptionNotice, 2)
    }

    func testTheMigrationMarkIsOffUntilSetAndThenSticks() {
        XCTAssertFalse(store().isAccountListsMigrated())

        store().markAccountListsMigrated()

        XCTAssertTrue(store().isAccountListsMigrated())
    }

    func testLocksAreRememberedPerListAndSurviveANewInstance() {
        let store = store()
        store.rememberLock(listId: "l1", locked: true)
        store.rememberLock(listId: "l2", locked: true)

        XCTAssertEqual(self.store().lockedListIds(), ["l1", "l2"])
    }

    func testUnlockingForgetsJustThatList() {
        let store = store()
        store.rememberLock(listId: "l1", locked: true)
        store.rememberLock(listId: "l2", locked: true)

        store.rememberLock(listId: "l1", locked: false)

        XCTAssertEqual(store.lockedListIds(), ["l2"])
    }

    func testForgetAllLocksClearsEveryRememberedLock() {
        let store = store()
        store.rememberLock(listId: "l1", locked: true)

        store.forgetAllLocks()

        XCTAssertTrue(self.store().lockedListIds().isEmpty)
    }

    func testUnverifiedIdsAreEmptyUntilSetAndAreReplacedWholesale() {
        let store = store()
        XCTAssertTrue(store.unverifiedListIds().isEmpty)

        store.setUnverifiedListIds(["a", "b"])
        store.setUnverifiedListIds(["c"])

        XCTAssertEqual(self.store().unverifiedListIds(), ["c"])
    }
}
