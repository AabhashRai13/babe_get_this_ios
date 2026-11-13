import XCTest
@testable import BabeGetThis

/// Port of Android WelcomeViewModelTest.
@MainActor
final class WelcomeViewModelTests: XCTestCase {
    private final class RecordingAnalytics: WelcomeAnalytics, @unchecked Sendable {
        private(set) var choices: [WelcomeChoice] = []
        func track(choice: WelcomeChoice) { choices.append(choice) }
    }

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var welcome: WelcomeRepository!
    private var analytics: RecordingAnalytics!
    private var viewModel: WelcomeViewModel!

    override func setUp() {
        super.setUp()
        suiteName = "welcome-vm-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        welcome = WelcomeRepository(defaults: defaults, isUpdateInstall: { false })
        analytics = RecordingAnalytics()
        viewModel = WelcomeViewModel(welcome: welcome, analytics: analytics)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testContinueAsGuestMarksWelcomeDoneAndReportsGuest() {
        viewModel.onContinueAsGuest()

        XCTAssertFalse(welcome.shouldShowWelcome(authState: .unauthenticated))
        XCTAssertEqual(analytics.choices, [.guest])
    }

    /// Backing out of Login must land on Welcome again, so tapping Sign in records the choice
    /// but not that Welcome is done.
    func testSignInReportsSignInAndLeavesWelcomePending() {
        viewModel.onSignIn()

        XCTAssertTrue(welcome.shouldShowWelcome(authState: .unauthenticated))
        XCTAssertEqual(analytics.choices, [.signIn])
    }
}
