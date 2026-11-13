import XCTest
@testable import BabeGetThis

/// Port of Android WelcomeRepositoryTest, on a real UserDefaults suite: what matters is what
/// survives between reads and app updates.
final class WelcomeRepositoryTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var updateInstall = false
    private var repository: WelcomeRepository!

    override func setUp() {
        super.setUp()
        suiteName = "welcome-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        updateInstall = false
        repository = WelcomeRepository(defaults: defaults, isUpdateInstall: { [unowned self] in updateInstall })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        repository = nil
        super.tearDown()
    }

    func testFreshInstallSignedOutSeesWelcome() {
        XCTAssertTrue(repository.shouldShowWelcome(authState: .unauthenticated))
    }

    /// Existing users updating to this version have already been using the app.
    func testUpdatedInstallNeverSeesWelcome() {
        updateInstall = true

        XCTAssertFalse(repository.shouldShowWelcome(authState: .unauthenticated))
    }

    /// A fresh install that gets an app update before anyone chose still owes the user the
    /// choice: the first answer is persisted, not recomputed.
    func testFirstAnswerSticksAcrossLaterAppUpdate() {
        _ = repository.shouldShowWelcome(authState: .unauthenticated)

        updateInstall = true

        XCTAssertTrue(repository.shouldShowWelcome(authState: .unauthenticated))
    }

    func testSignedInExpiredOrLoadingUserNeverSeesWelcome() {
        XCTAssertFalse(repository.shouldShowWelcome(authState: .authenticated(userId: "u1")))
        XCTAssertFalse(repository.shouldShowWelcome(authState: .sessionExpired(userId: "u1")))
        XCTAssertFalse(repository.shouldShowWelcome(authState: .loading))
    }

    func testContinuingAsGuestHidesWelcomeAndSigningOutShowsItAgain() {
        repository.markDone()
        XCTAssertFalse(repository.shouldShowWelcome(authState: .unauthenticated))

        repository.reset()
        XCTAssertTrue(repository.shouldShowWelcome(authState: .unauthenticated))
    }

    func testSigningOutShowsWelcomeEvenOnUpdatedInstall() {
        updateInstall = true

        repository.reset()

        XCTAssertTrue(repository.shouldShowWelcome(authState: .unauthenticated))
    }

    func testGuestChoiceSurvivesANewRepositoryOnTheSameSuite() {
        repository.markDone()

        let reopened = WelcomeRepository(defaults: UserDefaults(suiteName: suiteName)!, isUpdateInstall: { false })

        XCTAssertFalse(reopened.shouldShowWelcome(authState: .unauthenticated))
    }
}
