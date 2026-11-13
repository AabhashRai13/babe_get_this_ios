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

    func testSignedOutShareLivePromptsWithShareCopyNotVoiceCopy() {
        let model = makeModel(.unauthenticated)
        model.perform(.shareLive)
        XCTAssertEqual(model.authPrompt?.title, "Sign in to share")
        XCTAssertFalse(model.isShareLivePresented)
    }

    func testSignedInShareLiveOpensPlaceholder() {
        let model = makeModel(.authenticated(userId: "u1"))
        model.perform(.shareLive)
        XCTAssertTrue(model.isShareLivePresented)
    }

    func testShareAsTextSharesTheListNameForNow() {
        let model = makeModel(.unauthenticated)
        model.perform(.shareAsText)
        XCTAssertEqual(model.sharedText, "Groceries")
    }
}
