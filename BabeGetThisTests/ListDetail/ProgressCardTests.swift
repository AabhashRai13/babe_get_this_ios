import XCTest
@testable import BabeGetThis

/// Android `ProgressCard`: the celebration (card pop, check pop, colour pulse) skips the first
/// composition (`hasInitialized`) and replays only on the change to finished.
final class ProgressCardTests: XCTestCase {
    func testCelebrationPlaysOnlyOnTransitionToFinished() {
        var celebration = ProgressCardCelebration()

        // First value shown: never celebrates, finished or not.
        XCTAssertFalse(celebration.update(allDone: false))
        // Ticking the last item: not finished -> finished celebrates.
        XCTAssertTrue(celebration.update(allDone: true))
        // Staying finished doesn't replay it.
        XCTAssertFalse(celebration.update(allDone: true))
        // Unticking resets quietly; finishing again celebrates again.
        XCTAssertFalse(celebration.update(allDone: false))
        XCTAssertFalse(celebration.update(allDone: false))
        XCTAssertTrue(celebration.update(allDone: true))
    }

    func testOpeningAFinishedListDoesNotCelebrate() {
        var celebration = ProgressCardCelebration()

        XCTAssertFalse(celebration.update(allDone: true))
        XCTAssertFalse(celebration.update(allDone: true))
        // Only after it has been seen unfinished does finishing celebrate.
        XCTAssertFalse(celebration.update(allDone: false))
        XCTAssertTrue(celebration.update(allDone: true))
    }
}
