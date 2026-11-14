import XCTest
@testable import BabeGetThis

/// The list detail chrome's side of Share live: the sheet opens only once the share produced a
/// code (Android shows `ShareCodeDialog` only on `Result.Success`); a failure never opens it and
/// goes to the detail screen's snackbar; a lost session gets the share sign-in prompt.
@MainActor
final class ShareLiveChromeTests: XCTestCase {
    private var errors: [String] = []

    override func setUp() async throws {
        errors = []
    }

    private func chrome(result: Result<String, AppError>,
                        shareAuth: AuthState = .authenticated(userId: "user-1")) -> ListDetailChromeModel {
        let shareLive = ShareLiveViewModel(
            listId: "L1", authState: { shareAuth }, sharer: ChromeFakeSharer(result: result),
            reportError: { [unowned self] in errors.append($0) }, copyToClipboard: { _ in })
        return ListDetailChromeModel(listName: "Groceries", authState: { .authenticated(userId: "user-1") },
                                     shareLive: shareLive)
    }

    func testShareLiveOpensTheSheetOnceTheCodeArrives() async {
        let chrome = chrome(result: .success("ABC234"))

        chrome.perform(.shareLive)
        await chrome.shareTask?.value

        XCTAssertTrue(chrome.isShareLivePresented)
        XCTAssertEqual(chrome.shareLive?.shareCode, "ABC234")
        XCTAssertNil(chrome.authPrompt)
        XCTAssertEqual(errors, [])
    }

    func testAFailedShareNeverOpensTheSheetAndReportsTheError() async {
        let chrome = chrome(result: .failure(.network()))

        chrome.perform(.shareLive)
        await chrome.shareTask?.value

        XCTAssertFalse(chrome.isShareLivePresented, "no dialog is shown")
        XCTAssertEqual(errors, [AppError.network().message])
        XCTAssertNil(chrome.authPrompt)
    }

    func testDoneClosesTheSheetAndDropsTheCode() async {
        let chrome = chrome(result: .success("ABC234"))
        chrome.perform(.shareLive)
        await chrome.shareTask?.value

        chrome.isShareLivePresented = false

        XCTAssertFalse(chrome.isShareLivePresented)
        XCTAssertNil(chrome.shareLive?.shareCode)
    }

    func testASessionLostBeforeTheShareShowsTheSharePrompt() async {
        let chrome = chrome(result: .success("ABC234"), shareAuth: .sessionExpired(userId: "user-1"))

        chrome.perform(.shareLive)
        await chrome.shareTask?.value

        XCTAssertFalse(chrome.isShareLivePresented)
        XCTAssertEqual(chrome.authPrompt, .share)
        XCTAssertEqual(chrome.shareLive?.showsAuthPrompt, false)
    }
}

private final class ChromeFakeSharer: ListSharing, @unchecked Sendable {
    private let result: Result<String, AppError>

    init(result: Result<String, AppError>) {
        self.result = result
    }

    func share(listId: String) async throws -> Result<String, AppError> { result }
}
