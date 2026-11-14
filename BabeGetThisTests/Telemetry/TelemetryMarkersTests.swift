import XCTest
@testable import BabeGetThis

/// Port of Android's TelemetryMarkersTest. Real UserDefaults (a per-test suite) so "once"
/// survives the object being recreated, which is what a relaunch looks like.
final class TelemetryMarkersTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TelemetryMarkersTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func markers() -> TelemetryMarkers { TelemetryMarkers(defaults: defaults) }

    func testTheFirstClaimSucceedsAndEveryLaterOneFails() {
        let markers = markers()

        XCTAssertTrue(markers.firstTime(.firstItemAdded, scope: "user-1"))
        XCTAssertFalse(markers.firstTime(.firstItemAdded, scope: "user-1"))
    }

    func testAClaimIsRememberedAcrossInstances() {
        _ = markers().firstTime(.firstItemAdded, scope: "user-1")

        XCTAssertFalse(markers().firstTime(.firstItemAdded, scope: "user-1"))
    }

    func testScopesAreIndependent() {
        // A second account on the same device records its own activation.
        let markers = markers()
        _ = markers.firstTime(.firstItemAdded, scope: "user-1")

        XCTAssertTrue(markers.firstTime(.firstItemAdded, scope: "user-2"))
    }

    func testMarkersAreIndependentWithinAScope() {
        let markers = markers()
        _ = markers.firstTime(.firstItemAdded, scope: "user-1")

        XCTAssertTrue(markers.firstTime(.firstListCompleted, scope: "user-1"))
    }

    func testASignedOutUserHasAnAnonymousScopeOfTheirOwn() {
        let markers = markers()

        XCTAssertTrue(markers.firstTime(.firstItemAdded, scope: nil))
        XCTAssertFalse(markers.firstTime(.firstItemAdded, scope: nil))
        XCTAssertTrue(markers.firstTime(.firstItemAdded, scope: "user-1"))
    }

    func testMarkRecordsWithoutClaimingAndHasReadsWithoutClaiming() {
        let markers = markers()
        XCTAssertFalse(markers.has(.joinedList, scope: "list-1"))

        markers.mark(.joinedList, scope: "list-1")

        XCTAssertTrue(markers.has(.joinedList, scope: "list-1"))
        XCTAssertTrue(markers.has(.joinedList, scope: "list-1"))
    }
}
