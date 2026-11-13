import XCTest
@testable import BabeGetThis

/// Register and reset copy matches Android strings.xml.
final class AuthCopyTests: XCTestCase {
    func testRegisterHeaderAndNameFieldMatchAndroid() {
        XCTAssertEqual(AuthCopy.welcome, "Welcome to")
        XCTAssertEqual(AuthCopy.appName, "Babe, Get This")
        XCTAssertEqual(AuthCopy.registerSubtitle, "Create an account to start sharing lists")
        XCTAssertEqual(AuthCopy.name, "Your name")
    }

    func testResetCopyMatchesAndroidAndNamesTheEmail() {
        XCTAssertEqual(AuthCopy.resetPassword, "Reset password")
        XCTAssertEqual(AuthCopy.forgotSubtitle, "Enter your email and we'll send you an 8-digit code")
        XCTAssertEqual(AuthCopy.codeSent(to: "sam@example.com"),
                       "Enter the code we sent to sam@example.com and choose a new password")
    }

    func testVisibilityToggleNamesItsField() {
        XCTAssertEqual(AuthCopy.visibilityToggleLabel(isVisible: false), "Show password")
        XCTAssertEqual(AuthCopy.visibilityToggleLabel(isVisible: true), "Hide password")
        XCTAssertEqual(AuthCopy.visibilityToggleLabel(isVisible: false, field: "confirm password"),
                       "Show confirm password")
    }
}
