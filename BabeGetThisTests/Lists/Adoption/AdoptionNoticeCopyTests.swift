import XCTest
@testable import BabeGetThis

/// Android `adoption_notice` plurals and the dialog's button strings (HOME-15).
final class AdoptionNoticeCopyTests: XCTestCase {
    func testOneListUsesTheSingularCopy() {
        XCTAssertEqual(
            AdoptionNoticeCopy.message(count: 1),
            "Your list is now saved to your account, so it's backed up and shows up on any phone you sign in on.")
    }

    func testSeveralListsUseThePluralCopyWithTheCount() {
        XCTAssertEqual(
            AdoptionNoticeCopy.message(count: 3),
            "Your 3 lists are now saved to your account, so they're backed up and show up on any phone you sign in on.")
        XCTAssertTrue(AdoptionNoticeCopy.message(count: 2).hasPrefix("Your 2 lists are"))
    }

    func testButtonsAndPrivacyLinkMatchAndroid() {
        XCTAssertEqual(AdoptionNoticeCopy.ok, "OK")
        XCTAssertEqual(AdoptionNoticeCopy.privacyPolicy, "Privacy policy")
        XCTAssertEqual(AdoptionNoticeCopy.privacyPolicyURL.absoluteString, "https://babegetthis.com/privacy-policy.html")
    }
}
