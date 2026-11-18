import SwiftUI
import UIKit
import XCTest
@testable import BabeGetThis

/// Layout at the accessibility text sizes (Settings → Accessibility → Larger Text), found by
/// running the app at the largest size after the UI-08 polish pass.
@MainActor
final class AccessibilityTextSizeTests: XCTestCase {
    private let longName = "Groceries for the long weekend away"

    private func size<V: View>(of view: V, at type: DynamicTypeSize, width: CGFloat = 370) -> CGSize {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, type))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private func title3PointSize(at category: UIContentSizeCategory) -> CGFloat {
        UIFont.preferredFont(forTextStyle: .title3,
                             compatibleWith: UITraitCollection(preferredContentSizeCategory: category)).pointSize
    }

    // MARK: Icons keep their tile or circle around them

    private var tile: ListIconTile { ListIconTile(systemImage: "cart", accent: ListAccent(listId: "a")) }

    func testListTileIs48PointsAtTheDefaultSize() {
        XCTAssertEqual(size(of: tile, at: .large).width, 48, accuracy: 0.5)
    }

    // By default the tile is 48 pt around a 20 pt glyph. Before the fix it stayed 48 pt while the
    // glyph grew past it.
    func testListTileGrowsWithItsIcon() {
        let glyph = title3PointSize(at: .accessibilityMedium)
        XCTAssertGreaterThanOrEqual(size(of: tile, at: .accessibility1).width, 2 * glyph)
    }

    // Growing all the way, the tile reached ~130 pt and squeezed the list name beside it.
    func testListTileStopsGrowingAfterTheFirstAccessibilitySize() {
        XCTAssertEqual(size(of: tile, at: .accessibility5).width, size(of: tile, at: .accessibility1).width, accuracy: 0.5)
    }

    func testVoiceFABIs48PointsAtTheDefaultSize() {
        XCTAssertEqual(size(of: VoiceFABIcon(), at: .large).width, 48, accuracy: 0.5)
    }

    func testVoiceFABGrowsWithItsIcon() {
        let glyph = title3PointSize(at: .accessibilityMedium)
        XCTAssertGreaterThanOrEqual(size(of: VoiceFABIcon(), at: .accessibility1).width, 2 * glyph)
    }

    // Growing all the way, the FAB reached ~130 pt and covered the items under it.
    func testVoiceFABStopsGrowingAfterTheFirstAccessibilitySize() {
        XCTAssertEqual(size(of: VoiceFABIcon(), at: .accessibility5).width,
                       size(of: VoiceFABIcon(), at: .accessibility1).width, accuracy: 0.5)
    }

    // MARK: Names wrap instead of truncating at accessibility sizes

    private func listCardHeight(_ name: String, at type: DynamicTypeSize) -> CGFloat {
        let list = ShoppingListSummary(id: "a", name: name, totalItems: 5, pickedUpItems: 0, createdAt: .now)
        return size(of: ListCard(list: list), at: type).height
    }

    func testListNamesStayOnOneLineAtStandardSizes() {
        XCTAssertEqual(listCardHeight(longName, at: .xxxLarge), listCardHeight("Food", at: .xxxLarge), accuracy: 0.5)
    }

    func testListNamesWrapAtAccessibilitySizes() {
        XCTAssertGreaterThan(listCardHeight(longName, at: .accessibility3), listCardHeight("Food", at: .accessibility3))
    }

    // Beside the tile, the name's column was so narrow that "Sunday" broke as "Sun-day".
    func testListNamesGetTheCardsFullWidthAtAccessibilitySizes() {
        XCTAssertEqual(listCardHeight("Sunday", at: .accessibility5), listCardHeight("Sun", at: .accessibility5), accuracy: 0.5)
    }

    private func itemCardHeight(_ name: String, at type: DynamicTypeSize) -> CGFloat {
        size(of: ItemCardView(item: ShoppingItem(name: name, quantity: "1"), onToggle: {}), at: type).height
    }

    func testItemNamesStayOnOneLineAtStandardSizes() {
        XCTAssertEqual(itemCardHeight(longName, at: .xxxLarge), itemCardHeight("Milk", at: .xxxLarge), accuracy: 0.5)
    }

    func testItemNamesWrapAtAccessibilitySizes() {
        XCTAssertGreaterThan(itemCardHeight(longName, at: .accessibility3), itemCardHeight("Milk", at: .accessibility3))
    }

    // MARK: The Sign in pill never truncates

    // In the top bar the toolbar offered the pill less than its text needed and it showed "Sign…".
    func testSignInPillKeepsItsFullWidthWhenOfferedLess() {
        let pill = AccountControlButton(control: .signIn, action: {})
        let natural = size(of: pill, at: .xxxLarge, width: .greatestFiniteMagnitude).width
        XCTAssertEqual(size(of: pill, at: .xxxLarge, width: 40).width, natural, accuracy: 0.5)
    }

    // MARK: Side-by-side rows stack at accessibility sizes

    // Two half-width tabs broke "Completed" mid-word ("Com-plet-ed").
    func testTabPillsStackOnlyAtAccessibilitySizes() {
        XCTAssertFalse(TabPillRow.stacksVertically(at: .large))
        XCTAssertFalse(TabPillRow.stacksVertically(at: .xxxLarge))
        XCTAssertTrue(TabPillRow.stacksVertically(at: .accessibility1))
        XCTAssertTrue(TabPillRow.stacksVertically(at: .accessibility5))
    }

    // Icon, text and toggle in one row squeezed the text into a narrow column ("analyt-ics").
    func testSettingsRowsStackOnlyAtAccessibilitySizes() {
        XCTAssertFalse(SettingsRowLayout.stacksVertically(at: .xxxLarge))
        XCTAssertTrue(SettingsRowLayout.stacksVertically(at: .accessibility1))
    }
}
