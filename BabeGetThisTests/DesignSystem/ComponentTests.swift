import XCTest
@testable import BabeGetThis

@MainActor
final class RecordingHapticPlayer: HapticPlaying {
    private(set) var played: [Haptic] = []
    func play(_ haptic: Haptic) { played.append(haptic) }
}

@MainActor
final class HapticsTests: XCTestCase {
    func testHapticMapMatchesAndroid() {
        XCTAssertEqual(Haptic.light.effect, .lightImpact)
        XCTAssertEqual(Haptic.medium.effect, .mediumImpact)
        XCTAssertEqual(Haptic.heavy.effect, .mediumImpact)
        XCTAssertEqual(Haptic.success.effect, .mediumImpact)
        XCTAssertEqual(Haptic.allCases.count, 4)
    }
}

@MainActor
final class SwipeableCardTests: XCTestCase {
    func testSwipeFiresOncePerSettledSwipe() {
        let haptics = RecordingHapticPlayer()
        var lefts = 0
        var rights = 0
        let card = SwipeableCardController(onSwipeLeft: { lefts += 1 }, onSwipeRight: { rights += 1 }, haptics: haptics)

        // The permission check may be consulted repeatedly without firing anything.
        XCTAssertTrue(card.isAllowed(.towardLeading))
        XCTAssertTrue(card.isAllowed(.towardLeading))
        XCTAssertTrue(card.isAllowed(.towardTrailing))
        XCTAssertEqual(lefts, 0)
        XCTAssertEqual(rights, 0)

        card.settle(.towardLeading)
        XCTAssertEqual(lefts, 1)
        XCTAssertEqual(haptics.played, [.medium])

        card.settle(.towardTrailing)
        XCTAssertEqual(rights, 1)
        XCTAssertEqual(haptics.played, [.medium, .light])
    }

    func testRightSwipeDisallowedWithoutHandler() {
        let haptics = RecordingHapticPlayer()
        let card = SwipeableCardController(onSwipeLeft: {}, haptics: haptics)
        XCTAssertFalse(card.isAllowed(.towardTrailing))
        card.settle(.towardTrailing)
        XCTAssertTrue(haptics.played.isEmpty)
    }

    // Drag left to -150, then the next sample is already right of the start: with no right
    // action the card goes back to rest instead of keeping -150, and releasing there deletes nothing.
    func testDraggingBackAcrossTheStartDoesNotDelete() {
        var lefts = 0
        let card = SwipeableCardController(onSwipeLeft: { lefts += 1 }, haptics: RecordingHapticPlayer())

        XCTAssertEqual(card.offset(forTranslation: -150), -150)
        XCTAssertEqual(card.offset(forTranslation: 30), 0)
        card.end(translation: 30, velocity: 40)

        XCTAssertEqual(lefts, 0)
    }

    func testReleaseDecidesFromTheFinalTranslationAt56Points() {
        let card = SwipeableCardController(onSwipeLeft: {}, onSwipeRight: {}, haptics: RecordingHapticPlayer())
        XCTAssertNil(card.target(translation: -55, velocity: 0))
        XCTAssertEqual(card.target(translation: -56, velocity: 0), .towardLeading)
        XCTAssertEqual(card.target(translation: 56, velocity: 0), .towardTrailing)
        XCTAssertNil(card.target(translation: 0, velocity: 0))
    }

    func testAFlingDismissesBelowThePositionalThreshold() {
        let card = SwipeableCardController(onSwipeLeft: {}, onSwipeRight: {}, haptics: RecordingHapticPlayer())
        XCTAssertEqual(card.target(translation: -25, velocity: -125), .towardLeading)
        XCTAssertEqual(card.target(translation: 25, velocity: 400), .towardTrailing)
        XCTAssertNil(card.target(translation: -25, velocity: -124))
    }

    func testAFlingBackTowardRestSnapsBackEvenPastTheThreshold() {
        var lefts = 0
        let card = SwipeableCardController(onSwipeLeft: { lefts += 1 }, haptics: RecordingHapticPlayer())
        card.end(translation: -150, velocity: 600)
        XCTAssertEqual(lefts, 0)
    }

    func testADisallowedDirectionNeverSettles() {
        let card = SwipeableCardController(onSwipeLeft: {}, haptics: RecordingHapticPlayer())
        XCTAssertNil(card.target(translation: 200, velocity: 800))
        XCTAssertEqual(card.offset(forTranslation: 200), 0)
    }
}

@MainActor
final class TopAppBarTests: XCTestCase {
    func testNavAndActionTapsPlayLightHaptic() {
        let haptics = RecordingHapticPlayer()
        var navTaps = 0
        var actionTaps = 0
        let bar = TopAppBarActions(onNavigationTap: { navTaps += 1 }, onActionTap: { actionTaps += 1 }, haptics: haptics)

        bar.navigationTapped()
        bar.actionTapped()

        XCTAssertEqual(navTaps, 1)
        XCTAssertEqual(actionTaps, 1)
        XCTAssertEqual(haptics.played, [.light, .light])
    }

    func testMissingHandlersPlayNothing() {
        let haptics = RecordingHapticPlayer()
        let bar = TopAppBarActions(onNavigationTap: nil, onActionTap: nil, haptics: haptics)
        bar.navigationTapped()
        bar.actionTapped()
        XCTAssertTrue(haptics.played.isEmpty)
    }
}

@MainActor
final class SettingsRowTests: XCTestCase {
    func testARowShowsItsTitle() {
        let row = SettingsRowModel(title: "Change PIN", onTap: {})
        XCTAssertTrue(row.visibleTexts.contains("Change PIN"))
    }

    func testASubtitleIsShownWhenSupplied() {
        let row = SettingsRowModel(title: "Set up a PIN", subtitle: "Lock individual lists", onTap: {})
        XCTAssertTrue(row.visibleTexts.contains("Lock individual lists"))
    }

    func testNoSubtitleRowIsRenderedWhenNoneIsSupplied() {
        let row = SettingsRowModel(title: "Change PIN", onTap: {})
        XCTAssertFalse(row.visibleTexts.contains("Lock individual lists"))
        XCTAssertEqual(row.visibleTexts.count, 1)
    }

    func testTappingARowDispatchesItsCallback() {
        var clicked = false
        let row = SettingsRowModel(title: "Change PIN", onTap: { clicked = true })
        row.tap()
        XCTAssertTrue(clicked)
    }
}
