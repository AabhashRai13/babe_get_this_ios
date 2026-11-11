import XCTest
@testable import BabeGetThis

/// Port of Android's AppErrorTest. Every AppError's message is rendered directly to the user,
/// so the defaults are product copy rather than incidental strings.
final class AppErrorTests: XCTestCase {

    func testDefaultsAreUserFacingCopyNotExceptionJargon() {
        let defaults: [AppError] = [
            .database(),
            .network(),
            .server(code: 500),
            .timeout(),
            .notFound(),
            .auth(),
            .unauthorized(),
            .unknown(),
        ]

        for error in defaults {
            XCTAssertFalse(
                error.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "blank message on \(error)"
            )
            XCTAssertTrue(
                error.message.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("."),
                "\(error) should end in a sentence: \(error.message)"
            )
        }
    }

    func testEachDefaultReadsAsExpected() {
        XCTAssertEqual("Something went wrong. Please try again.", AppError.database().message)
        XCTAssertEqual("No internet connection.", AppError.network().message)
        XCTAssertEqual("Server error. Please try later.", AppError.server(code: 500).message)
        XCTAssertEqual("Request timed out. Please try again.", AppError.timeout().message)
        XCTAssertEqual("Item not found.", AppError.notFound().message)
        XCTAssertEqual("Authentication failed.", AppError.auth().message)
        XCTAssertEqual("Session expired. Please log in again.", AppError.unauthorized().message)
        XCTAssertEqual("An unexpected error occurred.", AppError.unknown().message)
    }

    func testEverySubtypeAcceptsAnOverride() {
        XCTAssertEqual("custom", AppError.database("custom").message)
        XCTAssertEqual("custom", AppError.network("custom").message)
        XCTAssertEqual("custom", AppError.server(code: 500, message: "custom").message)
        XCTAssertEqual("custom", AppError.timeout("custom").message)
        XCTAssertEqual("custom", AppError.validation("custom").message)
        XCTAssertEqual("custom", AppError.notFound("custom").message)
        XCTAssertEqual("custom", AppError.auth("custom").message)
        XCTAssertEqual("custom", AppError.unauthorized("custom").message)
        XCTAssertEqual("custom", AppError.unknown("custom").message)
    }

    // validation has no default on purpose: the caller must supply the copy.
    func testValidationErrorRequiresItsOwnMessage() {
        XCTAssertEqual("List name can't be empty.", AppError.validation("List name can't be empty.").message)
    }

    func testServerErrorCarriesTheStatusCodeAlongsideTheCopy() {
        let error = AppError.server(code: 503)

        guard case .server(let code, let message) = error else { return XCTFail("not a server error") }
        XCTAssertEqual(503, code)
        XCTAssertEqual("Server error. Please try later.", message)
        XCTAssertEqual("Server error. Please try later.", error.message)
    }

    // Equality is by value: view model tests compare an emitted error against an expected one.
    func testErrorsCompareByValue() {
        XCTAssertEqual(AppError.database(), AppError.database())
        XCTAssertEqual(AppError.server(code: 500), AppError.server(code: 500))
        XCTAssertNotEqual(AppError.server(code: 500), AppError.server(code: 503))
        XCTAssertNotEqual(AppError.network(), AppError.network("other"))
    }

    func testAppErrorExceptionCarriesItsErrorAndMirrorsTheMessage() {
        let error = AppError.validation("Item name can't be empty.")

        let exception = AppErrorException(error)

        XCTAssertEqual(error, exception.appError)
        XCTAssertEqual(error.message, exception.message)
        XCTAssertEqual(error.message, exception.localizedDescription)
    }
}
