import XCTest
@testable import BabeGetThis

/// Start screen from auth state + the guest choice (WEL-02, WEL-03, NAV-02).
final class StartScreenTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var welcome: WelcomeRepository!

    override func setUp() {
        super.setUp()
        suiteName = "start-screen-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        welcome = WelcomeRepository(defaults: defaults, isUpdateInstall: { false })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadingKeepsLaunchState() {
        XCTAssertEqual(StartScreen.resolve(authState: .loading, welcome: welcome), .launch)
    }

    func testSignedInAndExpiredGoToLists() {
        XCTAssertEqual(StartScreen.resolve(authState: .authenticated(userId: "u"), welcome: welcome), .lists)
        XCTAssertEqual(StartScreen.resolve(authState: .sessionExpired(userId: "u"), welcome: welcome), .lists)
    }

    func testSignedOutGoesToWelcomeUntilGuestChosen() {
        XCTAssertEqual(StartScreen.resolve(authState: .unauthenticated, welcome: welcome), .welcome)
        welcome.markDone()
        XCTAssertEqual(StartScreen.resolve(authState: .unauthenticated, welcome: welcome), .lists)
    }
}
