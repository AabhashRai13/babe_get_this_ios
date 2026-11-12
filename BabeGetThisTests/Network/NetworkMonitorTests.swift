import XCTest
@testable import BabeGetThis

/// Port of Android's NetworkMonitorTest. A fake path source stands in for NWPathMonitor,
/// so each path state is driven directly.
final class NetworkMonitorTests: XCTestCase {
    private var source: FakeNetworkPathSource!
    private var monitor: NetworkMonitor!

    override func setUp() {
        super.setUp()
        source = FakeNetworkPathSource()
        monitor = NetworkMonitor(source: source)
    }

    func testASatisfiedPathIsOnline() {
        source.path = NetworkPathSnapshot(status: .satisfied)

        XCTAssertTrue(monitor.isOnline())
    }

    // The captive-portal case: attached to a network that cannot carry traffic until a
    // connection is established, so it claims connectivity it cannot actually use.
    func testAPathThatRequiresConnectionIsTreatedAsOffline() {
        source.path = NetworkPathSnapshot(status: .requiresConnection)

        XCTAssertFalse(monitor.isOnline(), "a captive portal must read as offline")
    }

    func testAnUnsatisfiedPathIsOffline() {
        source.path = NetworkPathSnapshot(status: .unsatisfied)

        XCTAssertFalse(monitor.isOnline())
    }

    // Android only checks INTERNET + VALIDATED, never metering: cellular or Low Data Mode is online.
    func testAnExpensiveOrConstrainedSatisfiedPathIsStillOnline() {
        source.path = NetworkPathSnapshot(status: .satisfied, isExpensive: true, isConstrained: true)

        XCTAssertTrue(monitor.isOnline())
    }

    // Before the system reports a path the state is unknown, not offline: a gated call goes
    // ahead and fails on its own if it must, instead of a false "No internet connection.".
    func testAnUnknownPathIsTreatedAsOnline() {
        source.path = nil

        XCTAssertTrue(monitor.isOnline())
    }

    // Repeated reads must not cache: connectivity changes under the app.
    func testTheAnswerFollowsTheCurrentStateRatherThanBeingCached() {
        source.path = NetworkPathSnapshot(status: .satisfied)
        XCTAssertTrue(monitor.isOnline())

        source.path = NetworkPathSnapshot(status: .requiresConnection)

        XCTAssertFalse(monitor.isOnline())
    }

    // The source waits for the first real path rather than seeding the unevaluated placeholder.
    func testTheSystemSourceHasARealPathOnceCreated() {
        let system = SystemNetworkPathSource(firstPathTimeout: .seconds(2))

        XCTAssertNotNil(system.currentPath)
        _ = NetworkMonitor(source: system).isOnline()
    }

    func testTheDefaultMonitorSharesOneSystemSource() {
        XCTAssertTrue(SystemNetworkPathSource.shared === SystemNetworkPathSource.shared)
        _ = NetworkMonitor().isOnline()
    }
}

private final class FakeNetworkPathSource: NetworkPathSource, @unchecked Sendable {
    var path: NetworkPathSnapshot?
    var currentPath: NetworkPathSnapshot? { path }
}
