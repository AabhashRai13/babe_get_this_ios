import XCTest
@testable import BabeGetThis

/// Port of Android's BucketsTest, minus the 2 reminder-delay cases (reminders are out of v1).
/// Pins the edges exactly, which is where a `<` that should be `<=` hides.
final class BucketsTests: XCTestCase {

    func testCountBucketsLandOnTheDocumentedEdges() {
        XCTAssertEqual("0", Buckets.count(0))
        XCTAssertEqual("1", Buckets.count(1))
        XCTAssertEqual("2-5", Buckets.count(2))
        XCTAssertEqual("2-5", Buckets.count(5))
        XCTAssertEqual("6-10", Buckets.count(6))
        XCTAssertEqual("6-10", Buckets.count(10))
        XCTAssertEqual("11-20", Buckets.count(11))
        XCTAssertEqual("11-20", Buckets.count(20))
        XCTAssertEqual("21-50", Buckets.count(21))
        XCTAssertEqual("21-50", Buckets.count(50))
        XCTAssertEqual("50+", Buckets.count(51))
    }

    func testNegativeCountsCollapseIntoZeroRatherThanProducingANewLabel() {
        XCTAssertEqual("0", Buckets.count(-1))
        XCTAssertEqual("0", Buckets.count(Int.min))
    }

    func testLargeCountsStayInsideTheTopBucket() {
        XCTAssertEqual("50+", Buckets.count(4_318))
        XCTAssertEqual("50+", Buckets.count(Int.max))
    }

    func testDurationBucketsLandOnTheDocumentedEdges() {
        XCTAssertEqual("<1s", Buckets.millis(0))
        XCTAssertEqual("<1s", Buckets.millis(999))
        XCTAssertEqual("1-3s", Buckets.millis(1_000))
        XCTAssertEqual("1-3s", Buckets.millis(2_999))
        XCTAssertEqual("3-5s", Buckets.millis(3_000))
        XCTAssertEqual("3-5s", Buckets.millis(4_999))
        XCTAssertEqual("5-10s", Buckets.millis(5_000))
        XCTAssertEqual("5-10s", Buckets.millis(9_999))
        XCTAssertEqual("10-30s", Buckets.millis(10_000))
        XCTAssertEqual("10-30s", Buckets.millis(29_999))
        XCTAssertEqual("30s+", Buckets.millis(30_000))
    }

    func testANegativeDurationReportsUnknownRatherThanAFakeFastOne() {
        XCTAssertEqual("unknown", Buckets.millis(-1))
    }

    func testDaysAgoBucketsLandOnTheDocumentedEdges() {
        XCTAssertEqual("0", Buckets.daysAgo(0))
        XCTAssertEqual("1", Buckets.daysAgo(1))
        XCTAssertEqual("2-3", Buckets.daysAgo(2))
        XCTAssertEqual("2-3", Buckets.daysAgo(3))
        XCTAssertEqual("4-7", Buckets.daysAgo(4))
        XCTAssertEqual("4-7", Buckets.daysAgo(7))
        XCTAssertEqual("8-14", Buckets.daysAgo(8))
        XCTAssertEqual("8-14", Buckets.daysAgo(14))
        XCTAssertEqual("15-30", Buckets.daysAgo(15))
        XCTAssertEqual("15-30", Buckets.daysAgo(30))
        XCTAssertEqual("30+", Buckets.daysAgo(31))
    }

    func testANegativeAgeFallsIntoTheZeroBucket() {
        XCTAssertEqual("0", Buckets.daysAgo(-1))
    }

    func testErrorDaysBucketsLandOnTheDocumentedEdges() {
        XCTAssertEqual("<-7", Buckets.errorDays(-8))
        XCTAssertEqual("-7..-3", Buckets.errorDays(-7))
        XCTAssertEqual("-7..-3", Buckets.errorDays(-3))
        XCTAssertEqual("-2..2", Buckets.errorDays(-2))
        XCTAssertEqual("-2..2", Buckets.errorDays(0))
        XCTAssertEqual("-2..2", Buckets.errorDays(2))
        XCTAssertEqual("3..7", Buckets.errorDays(3))
        XCTAssertEqual("3..7", Buckets.errorDays(7))
        XCTAssertEqual(">7", Buckets.errorDays(8))
    }
}
