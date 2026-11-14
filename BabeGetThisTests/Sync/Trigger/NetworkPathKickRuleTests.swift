import XCTest
@testable import BabeGetThis

/// When `SystemNetworkAvailability` kicks (TRIG-02, Android `registerDefaultNetworkCallback`,
/// whose `onAvailable` fires for each new default network, a handover included).
final class NetworkPathKickRuleTests: XCTestCase {
    func testASatisfiedPathOnStartKicks() {
        var rule = NetworkPathKickRule()
        XCTAssertTrue(rule.update(satisfied: true, primaryInterface: "wifi:en0"))
    }

    func testAnUnsatisfiedPathNeverKicks() {
        var rule = NetworkPathKickRule()
        XCTAssertFalse(rule.update(satisfied: false, primaryInterface: nil))
        XCTAssertFalse(rule.update(satisfied: false, primaryInterface: nil))
    }

    func testConnectivityReturningKicks() {
        var rule = NetworkPathKickRule()
        _ = rule.update(satisfied: true, primaryInterface: "wifi:en0")
        XCTAssertFalse(rule.update(satisfied: false, primaryInterface: nil))
        XCTAssertTrue(rule.update(satisfied: true, primaryInterface: "wifi:en0"))
    }

    func testTheSamePathAgainDoesNotKick() {
        var rule = NetworkPathKickRule()
        _ = rule.update(satisfied: true, primaryInterface: "wifi:en0")
        XCTAssertFalse(rule.update(satisfied: true, primaryInterface: "wifi:en0"))
    }

    // Walking into the shop's Wi-Fi and out again: the path stays satisfied throughout.
    func testAHandoverBetweenWiFiAndCellularKicksEachWay() {
        var rule = NetworkPathKickRule()
        _ = rule.update(satisfied: true, primaryInterface: "cellular:pdp_ip0")

        XCTAssertTrue(rule.update(satisfied: true, primaryInterface: "wifi:en0"))
        XCTAssertFalse(rule.update(satisfied: true, primaryInterface: "wifi:en0"))
        XCTAssertTrue(rule.update(satisfied: true, primaryInterface: "cellular:pdp_ip0"))
    }
}
