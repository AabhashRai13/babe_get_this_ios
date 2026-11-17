import XCTest
@testable import BabeGetThis

/// Which screen is on top, from the screens' own appear and disappear calls (TEL-03). Android
/// reports from `OnDestinationChangedListener`, which fires whenever the current destination
/// changes: on a push, and again on the way back. These cases replay the orders SwiftUI uses.
@MainActor
final class ScreenTrackerTests: XCTestCase {
    private var reported: [Screen] = []
    private var queued: [@MainActor () -> Void] = []
    private let lists = UUID(), items = UUID(), login = UUID(), register = UUID()

    private lazy var tracker = ScreenTracker(
        report: { [unowned self] in reported.append($0) },
        schedule: { [unowned self] in queued.append($0) })

    /// Runs what the last SwiftUI update queued, as the main actor's next turn would.
    private func settle() {
        let work = queued
        queued = []
        work.forEach { $0() }
    }

    func testTheFirstScreenIsReported() {
        tracker.appeared(.shoppingList, id: lists)
        settle()

        XCTAssertEqual([.shoppingList], reported)
    }

    func testAPushedScreenIsReportedWhenItAppearsBeforeTheOneBelowDisappears() {
        tracker.appeared(.shoppingList, id: lists)
        settle()

        tracker.appeared(.shoppingItems, id: items)
        tracker.disappeared(id: lists)
        settle()

        XCTAssertEqual([.shoppingList, .shoppingItems], reported)
    }

    func testAPushedScreenIsReportedWhenTheOneBelowDisappearsFirst() {
        tracker.appeared(.shoppingList, id: lists)
        settle()

        tracker.disappeared(id: lists)
        tracker.appeared(.shoppingItems, id: items)
        settle()

        XCTAssertEqual([.shoppingList, .shoppingItems], reported)
    }

    // Android's listener fires for the destination it pops back to.
    func testGoingBackReportsTheScreenBelowAgain() {
        tracker.appeared(.shoppingList, id: lists)
        settle()
        tracker.appeared(.shoppingItems, id: items)
        tracker.disappeared(id: lists)
        settle()

        tracker.disappeared(id: items)
        tracker.appeared(.shoppingList, id: lists)
        settle()

        XCTAssertEqual([.shoppingList, .shoppingItems, .shoppingList], reported)
    }

    // A sheet leaves the screen below on screen, so that screen never disappears or appears
    // again. Auth is a destination on Android, so closing it reports the lists again.
    func testClosingASheetReportsTheScreenBelowAgain() {
        tracker.appeared(.shoppingList, id: lists)
        settle()
        tracker.appeared(.login, id: login)
        settle()

        tracker.disappeared(id: login)
        settle()

        XCTAssertEqual([.shoppingList, .login, .shoppingList], reported)
    }

    // Login and Register replace each other in one update: the lists below must not be
    // reported for the instant between them.
    func testSwappingScreensInOneUpdateReportsOnlyTheNewOne() {
        tracker.appeared(.shoppingList, id: lists)
        tracker.appeared(.login, id: login)
        settle()

        tracker.disappeared(id: login)
        tracker.appeared(.register, id: register)
        settle()

        XCTAssertEqual([.login, .register], reported)
    }

    func testAScreenAppearingAgainWithoutLeavingIsNotReportedTwice() {
        tracker.appeared(.shoppingList, id: lists)
        settle()

        tracker.appeared(.shoppingList, id: lists)
        settle()

        XCTAssertEqual([.shoppingList], reported)
    }

    func testNothingIsReportedWhenTheLastScreenGoes() {
        tracker.appeared(.welcome, id: lists)
        settle()

        tracker.disappeared(id: lists)
        settle()

        XCTAssertEqual([.welcome], reported)
    }

    func testByDefaultTheReportWaitsForTheNextMainActorTurn() async {
        var reported: [Screen] = []
        let tracker = ScreenTracker(report: { reported.append($0) })

        tracker.appeared(.settings, id: UUID())
        XCTAssertEqual([], reported, "the update that showed the screen may still swap it")

        for _ in 0..<100 where reported.isEmpty { await Task.yield() }
        XCTAssertEqual([.settings], reported)
    }
}
