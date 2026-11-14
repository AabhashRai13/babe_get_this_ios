import XCTest
@testable import BabeGetThis

/// The list detail chrome's side of Share live: the sheet hands a lost session back to it.
@MainActor
final class ShareLiveChromeTests: XCTestCase {
    func testShareLiveOpensTheSheetWhenSignedIn() {
        let chrome = ListDetailChromeModel(listName: "Groceries", authState: { .authenticated(userId: "user-1") })

        chrome.perform(.shareLive)

        XCTAssertTrue(chrome.isShareLivePresented)
        XCTAssertNil(chrome.authPrompt)
    }

    func testASessionLostInTheSheetClosesItAndShowsTheSharePrompt() {
        let chrome = ListDetailChromeModel(listName: "Groceries", authState: { .authenticated(userId: "user-1") })
        chrome.perform(.shareLive)

        chrome.shareLiveNeedsSignIn()

        XCTAssertFalse(chrome.isShareLivePresented)
        XCTAssertEqual(chrome.authPrompt, .share)
    }
}
