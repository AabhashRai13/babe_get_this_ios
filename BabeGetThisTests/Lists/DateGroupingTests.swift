import XCTest
@testable import BabeGetThis

/// Port of Android DateGroupingTest. Every case pins "now" explicitly, so the 7-day and
/// same-month boundaries don't depend on the date the suite runs.
final class DateGroupingTests: XCTestCase {
    private let calendar = Calendar.current

    // 2024-06-25 12:00:00 local. Mid-month and midday on purpose: room either side for
    // the same-month cases, and day arithmetic stays away from midnight/DST edges.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2024, month: 6, day: 25, hour: 12, minute: 0, second: 0))!
    }

    // Built from `now` with calendar arithmetic, the same way production does.
    private func daysBefore(_ days: Int, hoursOffset: Int = 0) -> Date {
        let shifted = calendar.date(byAdding: .day, value: -days, to: now)!
        return calendar.date(byAdding: .hour, value: hoursOffset, to: shifted)!
    }

    private func period(_ date: Date) -> TimePeriod {
        TimePeriod.of(date, now: now, calendar: calendar)
    }

    func testSameCalendarDayIsToday() {
        XCTAssertEqual(period(daysBefore(0, hoursOffset: -5)), .today)
    }

    func testStartOfTodayIsStillToday() {
        let startOfToday = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now)!
        XCTAssertEqual(period(startOfToday), .today)
    }

    func testPreviousCalendarDayIsYesterday() {
        XCTAssertEqual(period(daysBefore(1)), .yesterday)
    }

    func testTwoDaysAgoIsLastWeek() {
        XCTAssertEqual(period(daysBefore(2)), .lastWeek)
    }

    func testSixDaysAgoIsLastWeek() {
        XCTAssertEqual(period(daysBefore(6)), .lastWeek)
    }

    // The boundary is exclusive, so a timestamp exactly on the cutoff falls through to the month check.
    func testExactlySevenDaysAgoFallsThroughToThisMonth() {
        XCTAssertEqual(period(daysBefore(7)), .thisMonth)
    }

    func testJustInsideSevenDaysIsLastWeek() {
        XCTAssertEqual(period(daysBefore(7).addingTimeInterval(0.001)), .lastWeek)
    }

    func testEarlierInTheSameMonthIsThisMonth() {
        // 2024-06-05, still June.
        XCTAssertEqual(period(daysBefore(20)), .thisMonth)
    }

    func testPreviousMonthIsOlder() {
        // 2024-05-26.
        XCTAssertEqual(period(daysBefore(30)), .older)
    }

    func testSameMonthInAPreviousYearIsOlder() {
        let lastYear = calendar.date(byAdding: .year, value: -1, to: now)!
        XCTAssertEqual(period(lastYear), .older)
    }

    // Pins current behaviour rather than endorsing it: a future timestamp is after
    // the 7-day cutoff, so it reads as Last 7 Days.
    func testFutureTimestampReadsAsLastWeek() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(period(tomorrow), .lastWeek)
    }

    func testDisplayNameCoversEveryPeriod() {
        XCTAssertEqual(TimePeriod.today.displayName, "Today")
        XCTAssertEqual(TimePeriod.yesterday.displayName, "Yesterday")
        XCTAssertEqual(TimePeriod.lastWeek.displayName, "Last 7 Days")
        XCTAssertEqual(TimePeriod.thisMonth.displayName, "This Month")
        XCTAssertEqual(TimePeriod.older.displayName, "Older")
    }

    func testDisplayNameIsExhaustiveOverTheEnum() {
        XCTAssertEqual(TimePeriod.allCases.count, 5)
        for period in TimePeriod.allCases {
            XCTAssertFalse(period.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
