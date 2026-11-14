import XCTest
@testable import BabeGetThis

/// The share-live cases of Android `ShoppingItemsViewModelTest` (lines 1032, 1045, 1060). The
/// lock case (1014) is out of iOS v1.
@MainActor
final class ShareLiveViewModelTests: XCTestCase {
    private func viewModel(auth: AuthState, sharer: FakeListSharer,
                           copied: CopiedText = CopiedText()) -> ShareLiveViewModel {
        ShareLiveViewModel(listId: "L1", authState: { auth }, sharer: sharer,
                           copyToClipboard: { copied.values.append($0) })
    }

    func testShareLivePromptsSignInWhenSignedOut() async {
        let sharer = FakeListSharer(result: .success("ABC234"))
        let vm = viewModel(auth: .unauthenticated, sharer: sharer)

        await vm.shareLive()

        XCTAssertTrue(vm.showsAuthPrompt)
        XCTAssertEqual(sharer.listIds, [])

        vm.dismissAuthPrompt()
        XCTAssertFalse(vm.showsAuthPrompt)
    }

    func testShareLiveShowsTheCodeDialogOnSuccess() async {
        let sharer = FakeListSharer(result: .success("ABC234"))
        let vm = viewModel(auth: .authenticated(userId: "user-1"), sharer: sharer)

        await vm.shareLive()

        XCTAssertEqual(vm.shareCode, "ABC234")
        XCTAssertEqual(sharer.listIds, ["L1"])

        vm.dismissShareCode()
        XCTAssertNil(vm.shareCode)
    }

    func testShareLiveSurfacesFailuresAsASnackbar() async {
        let sharer = FakeListSharer(result: .failure(.network()))
        let vm = viewModel(auth: .authenticated(userId: "user-1"), sharer: sharer)

        await vm.shareLive()

        XCTAssertEqual(vm.errorMessage, AppError.network().message)
        XCTAssertNil(vm.shareCode)
    }

    // A lost session keeps the user id but can't reach the server: it gets the prompt too.
    func testShareLivePromptsSignInWhenTheSessionExpired() async {
        let sharer = FakeListSharer(result: .success("ABC234"))
        let vm = viewModel(auth: .sessionExpired(userId: "user-1"), sharer: sharer)

        await vm.shareLive()

        XCTAssertTrue(vm.showsAuthPrompt)
        XCTAssertEqual(sharer.listIds, [])
    }

    func testCopyPutsTheCodeOnTheClipboard() async {
        let copied = CopiedText()
        let vm = viewModel(auth: .authenticated(userId: "user-1"),
                           sharer: FakeListSharer(result: .success("ABC234")), copied: copied)
        await vm.shareLive()

        vm.copyCode()

        XCTAssertEqual(copied.values, ["ABC234"])
    }

    func testIsSharingOnlyWhileTheShareRuns() async {
        let sharer = FakeListSharer(result: .success("ABC234"))
        let vm = viewModel(auth: .authenticated(userId: "user-1"), sharer: sharer)
        var seenWhileSharing: Bool?
        sharer.onShare = { @MainActor in seenWhileSharing = vm.isSharing }

        await vm.shareLive()

        XCTAssertEqual(seenWhileSharing, true)
        XCTAssertFalse(vm.isSharing)
    }

    // SHARE-06: the dialog shows only the code and the hint; nothing about who changed what.
    func testTheDialogCopyIsAndroidsWording() {
        XCTAssertEqual(ShareLiveCopy.title, "Share list live")
        XCTAssertEqual(ShareLiveCopy.hint,
                       "Anyone with this code can see and edit this list. Text it to them, and they enter it under \"Join a shared list\".")
        XCTAssertEqual(ShareLiveCopy.copy, "Copy")
        XCTAssertEqual(ShareLiveCopy.done, "Done")
    }
}

@MainActor
private final class CopiedText {
    var values: [String] = []
}

private final class FakeListSharer: ListSharing, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<String, AppError>
    private var shared: [String] = []
    var onShare: (@MainActor () -> Void)?

    init(result: Result<String, AppError>) {
        self.result = result
    }

    var listIds: [String] { lock.withLock { shared } }

    func share(listId: String) async throws -> Result<String, AppError> {
        lock.withLock { shared.append(listId) }
        if let onShare { await onShare() }
        return result
    }
}
