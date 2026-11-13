import Foundation
import Supabase
import XCTest
@testable import BabeGetThis

/// Port of Android's AuthErrorMapperTest. Kotlin's exception `cause` is the
/// `NSUnderlyingErrorKey` chain here, and its `message` is the error description.
final class AuthErrorMapperTests: XCTestCase {
    private func wrap(_ domain: String, _ underlying: any Error) -> NSError {
        NSError(domain: domain, code: 1, userInfo: [NSUnderlyingErrorKey: underlying])
    }

    private func friendly(_ message: String?) -> String {
        AuthErrorMapper.friendlyMessage(for: AuthMapperTestFailure(message: message))
    }

    // MARK: - isNetworkFailure

    func testATopLevelTransportErrorIsANetworkFailure() {
        XCTAssertTrue(AuthErrorMapper.isNetworkFailure(URLError(.cannotFindHost)))
        XCTAssertTrue(AuthErrorMapper.isNetworkFailure(URLError(.cannotConnectToHost)))
        XCTAssertTrue(AuthErrorMapper.isNetworkFailure(URLError(.timedOut)))
        XCTAssertTrue(AuthErrorMapper.isNetworkFailure(URLError(.notConnectedToInternet)))
        XCTAssertTrue(AuthErrorMapper.isNetworkFailure(POSIXError(.ECONNRESET)))
        XCTAssertTrue(AuthErrorMapper.isNetworkFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)))
    }

    func testAnOrdinaryErrorIsNotANetworkFailure() {
        XCTAssertFalse(AuthErrorMapper.isNetworkFailure(AuthMapperTestFailure(message: "nope")))
    }

    // The whole reason this walks the chain: the real transport error ends up wrapped
    // several causes deep, so a top-level type check reports a dropped connection as
    // bad credentials.
    func testATransportErrorBuriedInTheCauseChainStillCounts() {
        let buried = wrap("wrapper", wrap("inner", URLError(.cannotFindHost)))

        XCTAssertTrue(AuthErrorMapper.isNetworkFailure(buried))
    }

    func testADeepChainWithNoTransportCauseDoesNotCount() {
        let deep = wrap("a", wrap("b", AuthMapperTestFailure(message: "c")))

        XCTAssertFalse(AuthErrorMapper.isNetworkFailure(deep))
    }

    // A self-referential cause would spin forever without the cycle guard.
    func testACyclicCauseChainTerminates() {
        let a = AuthMapperCyclicFailure()
        let b = AuthMapperCyclicFailure()
        b.cause = a
        a.cause = b

        XCTAssertFalse(AuthErrorMapper.isNetworkFailure(a))
    }

    // MARK: - friendlyMessage

    func testBadCredentialsGetTheirOwnMessage() {
        XCTAssertEqual(friendly("Invalid login credentials"), "Invalid email or password.")
    }

    func testATakenEmailIsCalledOut() {
        XCTAssertEqual(friendly("User already registered"), "That email is already registered.")
        XCTAssertEqual(friendly("Email has already been registered"), "That email is already registered.")
    }

    func testAnUnconfirmedEmailIsExplained() {
        XCTAssertEqual(friendly("Email not confirmed"), "Please confirm your email before signing in.")
    }

    func testAnExpiredCodeIsExplained() {
        XCTAssertEqual(friendly("Token has expired"), "That code has expired. Request a new one.")
    }

    func testAnOtpOrTokenProblemIsExplained() {
        XCTAssertEqual(friendly("Invalid otp"), "Invalid code. Check the email and try again.")
        XCTAssertEqual(friendly("Bad token supplied"), "Invalid code. Check the email and try again.")
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(friendly("INVALID LOGIN CREDENTIALS"), "Invalid email or password.")
    }

    // "expired" is checked before "token", so an expired token reads as expired rather
    // than as an invalid code. Pinned because the ordering is load-bearing and both
    // branches match that string.
    func testExpiredWinsOverTokenWhenAMessageContainsBoth() {
        XCTAssertEqual(friendly("token expired"), "That code has expired. Request a new one.")
    }

    // Google ID-token rejections mention "id_token"/"ID token" or "nonce". They must not
    // fall through to the email-code branches, which would tell a Google user to check
    // an email code that was never sent.
    func testGoogleIdTokenRejectionsGetTheGoogleMessage() {
        let google = AuthErrorMapper.googleSignInFailed

        XCTAssertEqual(friendly("Unacceptable audience in id_token: [abc]"), google)
        XCTAssertEqual(friendly("Bad ID token"), google)
        XCTAssertEqual(friendly("Nonces mismatch"), google)
        XCTAssertEqual(friendly("id_token has expired"), google)
    }

    // The point of the fallback: never surface raw provider wording.
    func testAnUnrecognisedMessageIsReplacedNotPassedThrough() {
        let raw = "PGRST301: JWT sub claim missing from role mapping"

        let message = friendly(raw)

        XCTAssertEqual(message, "Authentication failed. Please try again.")
        XCTAssertFalse(message.contains("PGRST301"))
    }

    func testAnErrorWithNoMessageStillYieldsCopy() {
        XCTAssertEqual(friendly(nil), "Authentication failed. Please try again.")
        XCTAssertEqual(
            AuthErrorMapper.friendlyMessage(for: AuthMapperSilentFailure()),
            "Authentication failed. Please try again."
        )
    }

    // MARK: - iOS: the message of a real supabase-swift error

    func testASupabaseAuthApiErrorIsMappedByItsMessage() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:54321/auth/v1/token")!, statusCode: 400,
            httpVersion: "HTTP/1.1", headerFields: nil
        ))
        let error = AuthError.api(
            message: "Invalid login credentials", errorCode: .invalidCredentials,
            underlyingData: Data(), underlyingResponse: response
        )

        XCTAssertEqual(AuthErrorMapper.friendlyMessage(for: error), "Invalid email or password.")
        XCTAssertFalse(AuthErrorMapper.isNetworkFailure(error))
    }
}

/// An error carrying a message, like a Kotlin `Exception(message)`.
struct AuthMapperTestFailure: LocalizedError {
    let message: String?
    var errorDescription: String? { message }
}

/// An error with no message at all.
struct AuthMapperSilentFailure: Error {}

/// An error whose cause can point back at itself through `NSUnderlyingErrorKey`.
final class AuthMapperCyclicFailure: CustomNSError, @unchecked Sendable {
    var cause: (any Error)?

    static var errorDomain: String { "AuthMapperCyclicFailure" }
    var errorCode: Int { 1 }
    var errorUserInfo: [String: Any] {
        guard let cause else { return [:] }
        return [NSUnderlyingErrorKey: cause]
    }
}
