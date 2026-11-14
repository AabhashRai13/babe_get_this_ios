import XCTest
@testable import BabeGetThis

/// Ports the chrome tests of Android `ShoppingItemsScreenTest` (voice gate, top-bar actions).
@MainActor
final class ListDetailChromeTests: XCTestCase {
    private final class RecordingHaptics: HapticPlaying {
        var played: [Haptic] = []
        func play(_ haptic: Haptic) { played.append(haptic) }
    }

    private func makeModel(_ state: AuthState, haptics: RecordingHaptics = RecordingHaptics()) -> ListDetailChromeModel {
        ListDetailChromeModel(listName: "Groceries", authState: { state }, haptics: haptics)
    }

    func testVoiceFabPromptsSignInUnlessAuthenticated() {
        for state in [AuthState.unauthenticated, .loading, .sessionExpired(userId: "u1")] {
            let haptics = RecordingHaptics()
            let model = makeModel(state, haptics: haptics)
            model.voiceFabTapped()
            XCTAssertEqual(model.authPrompt, .voice, "\(state)")
            XCTAssertEqual(model.authPrompt?.title, "Sign in to use voice")
            XCTAssertFalse(model.isVoicePresented, "\(state)")
            XCTAssertEqual(haptics.played, [.medium])
        }

        let signedIn = makeModel(.authenticated(userId: "u1"))
        signedIn.voiceFabTapped()
        XCTAssertNil(signedIn.authPrompt)
        XCTAssertTrue(signedIn.isVoicePresented)
    }

    func testAuthPromptButtonsOpenLoginAndRegister() {
        let model = makeModel(.unauthenticated)
        model.voiceFabTapped()
        model.promptSignIn()
        XCTAssertNil(model.authPrompt)
        XCTAssertEqual(model.authRoute, .login)

        model.authRoute = nil
        model.voiceFabTapped()
        model.promptCreateAccount()
        XCTAssertEqual(model.authRoute, .register)
    }

    func testTopBarActionsAreShareLiveThenShareAsText() {
        XCTAssertEqual(ListDetailChromeModel.topBarActions.map(\.title), ["Share live", "Share as text"])
    }

    // Android ShoppingItemsScreen: both top-bar IconButtons call haptic(Haptic.Light) first,
    // signed in or not.
    func testEachTopBarActionPlaysALightHaptic() {
        for state in [AuthState.unauthenticated, .authenticated(userId: "u1")] {
            for action in ListDetailChromeModel.topBarActions {
                let haptics = RecordingHaptics()
                let model = makeModel(state, haptics: haptics)
                model.perform(action)
                XCTAssertEqual(haptics.played, [.light], "\(action) \(state)")
            }
        }
    }

    func testSignedOutShareLivePromptsWithShareCopyNotVoiceCopy() {
        let model = makeModel(.unauthenticated)
        model.perform(.shareLive)
        XCTAssertEqual(model.authPrompt?.title, "Sign in to share")
        XCTAssertFalse(model.isShareLivePresented)
    }

    func testSignedInShareLiveOpensTheSheetWithTheCode() async {
        let shareLive = ShareLiveViewModel(listId: "L1", authState: { .authenticated(userId: "u1") },
                                           sharer: CodeSharer(), reportError: { _ in },
                                           copyToClipboard: { _ in })
        let model = ListDetailChromeModel(listName: "Groceries", authState: { .authenticated(userId: "u1") },
                                          haptics: RecordingHaptics(), shareLive: shareLive)
        model.perform(.shareLive)
        await model.shareTask?.value
        XCTAssertTrue(model.isShareLivePresented)
        XCTAssertEqual(shareLive.shareCode, "ABC234")
    }

    private struct CodeSharer: ListSharing {
        func share(listId: String) async throws -> Result<String, AppError> { .success("ABC234") }
    }

    // The screen's wiring: the chrome reads the detail view model's live items and formats
    // them itself, so the shared text follows the items shown, not a snapshot.
    func testShareAsTextFormatsTheScreensLiveItems() async {
        let source = FakeListDetailItemsSource()
        let viewModel = ListDetailViewModel(listId: "L1", source: source, haptics: RecordingHapticPlayer())
        let observing = Task { await viewModel.observeItems() }
        defer { observing.cancel() }
        let model = ListDetailChromeModel(listName: "Groceries", authState: { .unauthenticated },
                                          haptics: RecordingHaptics(), items: { viewModel.items })

        source.send([TestData.storedItem("1", name: "Milk")])
        await listDetailEventually { viewModel.items.map(\.name) == ["Milk"] }
        model.perform(.shareAsText)
        XCTAssertEqual(model.sharedText, ShoppingListShareText.format(listName: "Groceries", items: viewModel.items))
        XCTAssertTrue(model.sharedText?.contains("Milk") == true)
        model.shareSheetFinished()

        source.send([TestData.storedItem("1", name: "Milk"), TestData.storedItem("2", name: "Eggs")])
        await listDetailEventually { viewModel.items.count == 2 }
        model.perform(.shareAsText)
        XCTAssertEqual(model.sharedText, ShoppingListShareText.format(listName: "Groceries", items: viewModel.items))
        XCTAssertTrue(model.sharedText?.contains("Eggs") == true, "read live, not captured earlier")
    }

    // The activity controller closes itself; the screen reports it so the next tap shares again.
    func testFinishingTheShareSheetClearsItAndASecondShareWorks() {
        let model = makeModel(.unauthenticated)
        model.perform(.shareAsText)
        XCTAssertNotNil(model.sharedText)

        model.shareSheetFinished()
        XCTAssertNil(model.sharedText)

        model.perform(.shareAsText)
        XCTAssertNotNil(model.sharedText)
    }
}
