import XCTest
@testable import BabeGetThis

/// The "sign in to continue" prompt names the feature it gates (Android AuthPromptDialog:
/// title and body are required so the share gate never says "Sign in to use voice").
final class AuthPromptTests: XCTestCase {
    func testPromptNamesTheGatedFeature() {
        XCTAssertEqual(AuthPromptContent.voice.title, "Sign in to use voice")
        XCTAssertEqual(AuthPromptContent.voice.body, "Create an account to capture shopping lists by voice.")
        XCTAssertEqual(AuthPromptContent.share.title, "Sign in to share")
        XCTAssertNotEqual(AuthPromptContent.share.title, AuthPromptContent.voice.title)
        XCTAssertFalse(AuthPromptContent.share.title.localizedCaseInsensitiveContains("voice"))
    }

    func testPromptOffersSignInAndCreateAccount() {
        XCTAssertEqual(AuthPromptContent.confirmTitle, "Sign in")
        XCTAssertEqual(AuthPromptContent.dismissTitle, "Create account")
    }
}
