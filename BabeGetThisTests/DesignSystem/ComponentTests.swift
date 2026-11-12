import SwiftUI
import UIKit
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

/// Port of Android SettingsRowTest: renders the row and asserts on what is shown and tapped.
@MainActor
final class SettingsRowTests: XCTestCase {
    func testARowShowsItsTitle() throws {
        let hosted = HostedView(SettingsRow(title: "Change PIN", onTap: {}))
        XCTAssertNotNil(hosted.element(labelled: "Change PIN"))
    }

    func testASubtitleIsShownWhenSupplied() throws {
        let hosted = HostedView(SettingsRow(title: "Set up a PIN", subtitle: "Lock individual lists", onTap: {}))
        XCTAssertTrue(hosted.labels.contains { $0.contains("Lock individual lists") }, "labels: \(hosted.labels)")
    }

    func testNoSubtitleRowIsRenderedWhenNoneIsSupplied() throws {
        let hosted = HostedView(SettingsRow(title: "Change PIN", onTap: {}))
        XCTAssertFalse(hosted.labels.contains { $0.contains("Lock individual lists") })
        XCTAssertEqual(hosted.labels, ["Change PIN"])
    }

    func testTappingARowDispatchesItsCallback() throws {
        var clicked = false
        let hosted = HostedView(SettingsRow(title: "Change PIN", onTap: { clicked = true }))

        let row = try XCTUnwrap(hosted.element(labelled: "Change PIN"))
        XCTAssertTrue(row.accessibilityTraits.contains(.button))
        XCTAssertTrue(row.accessibilityActivate())

        XCTAssertTrue(clicked)
    }

    // With a trailing Toggle the row and the toggle are separate elements, so the toggle's
    // value and action stay reachable with VoiceOver.
    func testATrailingToggleIsItsOwnAccessibilityElement() throws {
        var rowTaps = 0
        let hosted = HostedView(SettingsRow(title: "Analytics", onTap: { rowTaps += 1 }) {
            Toggle("Share analytics", isOn: .constant(true)).labelsHidden()
        })

        let row = try XCTUnwrap(hosted.element(labelled: "Analytics"))
        let toggle = try XCTUnwrap(hosted.element(labelled: "Share analytics"))
        XCTAssertFalse(row === toggle)
        XCTAssertNotNil(toggle.accessibilityValue)
        XCTAssertTrue(row.accessibilityActivate())
        XCTAssertEqual(rowTaps, 1)
    }
}

/// Hosts a SwiftUI view in a window and reads its accessibility elements, so tests assert on
/// what is rendered rather than on a helper.
@MainActor
final class HostedView {
    private let window: UIWindow
    private let root: UIView

    /// SwiftUI only builds its accessibility tree while an assistive client is active. Turn on
    /// automation mode (what UI tests and accessibility snapshot tools do) for this test process.
    private static let accessibilityEnabled: Bool = {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else { return false }
        typealias SetEnabled = @convention(c) (Int32) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(1)
        return true
    }()

    init<V: View>(_ view: V) {
        precondition(Self.accessibilityEnabled, "could not enable accessibility automation")
        let host = UIHostingController(rootView: view)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        root = host.view
    }

    var elements: [NSObject] {
        var found: [NSObject] = []
        func walk(_ node: NSObject, depth: Int) {
            guard depth < 40 else { return }
            if node.isAccessibilityElement { found.append(node); return }
            if let children = node.accessibilityElements as? [NSObject], !children.isEmpty {
                children.forEach { walk($0, depth: depth + 1) }
                return
            }
            let count = node.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for i in 0..<count {
                    if let child = node.accessibilityElement(at: i) as? NSObject { walk(child, depth: depth + 1) }
                }
                return
            }
            (node as? UIView)?.subviews.forEach { walk($0, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return found
    }

    var labels: [String] { elements.compactMap(\.accessibilityLabel) }

    func element(labelled text: String) -> NSObject? {
        elements.first { ($0.accessibilityLabel ?? "").contains(text) }
    }
}

private extension UIAccessibilityCustomAction {
    func perform() {
        if let actionHandler { _ = actionHandler(self) }
    }
}
