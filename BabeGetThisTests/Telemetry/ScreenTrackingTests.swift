import SwiftUI
import UIKit
import XCTest
@testable import BabeGetThis

/// TEL-03 from the real screens: the app is hosted in a window, navigation is driven through the
/// view models, and `screen_view` plus the per-screen crash keys must reach the container's
/// telemetry. Each screen reports as it comes on top, and again when what covered it goes away,
/// the way Android's destination listener does.
@MainActor
final class ScreenTrackingTests: XCTestCase {
    private var analytics: RecordingAnalytics!
    private var crashReporter: RecordingCrashReporter!
    private var scratch: ScratchMarkers!
    private var suiteName = ""
    private var window: UIWindow?

    override func setUp() async throws {
        try await super.setUp()
        analytics = RecordingAnalytics()
        crashReporter = RecordingCrashReporter()
        scratch = ScratchMarkers()
        suiteName = "screen-tracking-test-\(UUID().uuidString)"
        // On before anything is hosted: SwiftUI builds its accessibility tree only for an active client.
        XCTAssertTrue(HostedView.accessibilityEnabled, "could not enable accessibility automation")
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        scratch.remove()
        UserDefaults().removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    /// A signed-out guest on an in-memory database, never started, so nothing reaches the network.
    private func makeContainer(screen: StartScreen) throws -> AppContainer {
        let authState = AuthStateManager(tokenStore: InMemoryTokenStore())
        authState.initialize()
        return AppContainer(
            config: .preview, authState: authState, database: try AppDatabase.inMemory(),
            welcome: WelcomeRepository(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)),
                                       isUpdateInstall: { false }),
            forcedScreen: screen, ownership: FakeListOwnershipStore(),
            telemetry: TelemetryVendors(analytics: analytics, crashReporter: crashReporter),
            telemetryConsentStore: InMemoryTelemetryConsentStore(), telemetryMarkers: scratch.markers)
    }

    private func host(_ view: some View) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        self.window = window
    }

    /// The whole app, as `BabeGetThisApp` shows it.
    private func hostApp(_ container: AppContainer) throws {
        try host(RootView().environment(container))
    }

    /// Every `screen_view` so far, in order.
    private var screens: [Screen] {
        analytics.events.compactMap { event in
            if case .screenViewed(let screen) = event { screen } else { nil }
        }
    }

    /// Waits (up to 5 s: pushes and sheets animate first) for `screen` to be the latest reported.
    private func waitForScreen(_ screen: Screen, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 where screens.last != screen {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(screen, screens.last, "screens so far: \(screens)", file: file, line: line)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testTheListsReportThemselvesAndSetTheScreenCrashKeys() async throws {
        try hostApp(try makeContainer(screen: .lists))

        await waitForScreen(.shoppingList)
        XCTAssertEqual(["shopping_list"], crashReporter.values(for: .lastScreen))
        XCTAssertTrue(crashReporter.breadcrumbs.contains("screen: shopping_list"))
        let network = crashReporter.values(for: .networkState)
        XCTAssertEqual(1, network.count)
        XCTAssertTrue(["online", "offline"].contains(network.first ?? ""), "network_state: \(network)")
        // The data-shape keys are counted off the main actor, from the empty database.
        await waitUntil { !crashReporter.values(for: .syncQueueDepth).isEmpty }
        XCTAssertEqual(["0"], crashReporter.values(for: .itemCountBucket))
        XCTAssertEqual(["0"], crashReporter.values(for: .syncQueueDepth))
    }

    func testWelcomeReportsItself() async throws {
        try hostApp(try makeContainer(screen: .welcome))

        await waitForScreen(.welcome)
        XCTAssertEqual([.welcome], screens)
    }

    func testOpeningAListReportsTheListScreen() async throws {
        let container = try makeContainer(screen: .lists)
        try hostApp(container)
        await waitForScreen(.shoppingList)

        await container.lists.confirmCreate(named: "Weekly")

        await waitForScreen(.shoppingItems)
        XCTAssertEqual([.shoppingList, .shoppingItems], screens)
        XCTAssertEqual("shopping_items", crashReporter.values(for: .lastScreen).last)
    }

    func testSettingsReportsItselfAndLeavingItReportsTheListsAgain() async throws {
        let container = try makeContainer(screen: .lists)
        try hostApp(container)
        await waitForScreen(.shoppingList)

        container.lists.openSettings()
        await waitForScreen(.settings)
        container.lists.isSettingsPresented = false

        await waitForScreen(.shoppingList)
        XCTAssertEqual([.shoppingList, .settings, .shoppingList], screens)
    }

    func testSignInOverTheListsReportsLoginAndClosingItReportsTheListsAgain() async throws {
        let container = try makeContainer(screen: .lists)
        try hostApp(container)
        await waitForScreen(.shoppingList)

        container.lists.authRoute = .login
        await waitForScreen(.login)
        container.lists.authRoute = nil

        await waitForScreen(.shoppingList)
        XCTAssertEqual([.shoppingList, .login, .shoppingList], screens)
    }

    func testCreateAccountOverTheListsReportsRegister() async throws {
        let container = try makeContainer(screen: .lists)
        try hostApp(container)
        await waitForScreen(.shoppingList)

        container.lists.authRoute = .register

        await waitForScreen(.register)
        XCTAssertEqual([.shoppingList, .register], screens)
    }

    /// Waits (up to 5 s) for an element with this accessibility label anywhere in the window,
    /// sheets included, and activates it as VoiceOver would.
    private func tap(_ name: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let window = try XCTUnwrap(window)
        func find() -> NSObject? {
            HostedView.elements(under: window).first { $0.accessibilityLabel == name }
        }
        for _ in 0..<500 where find() == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let shown = HostedView.elements(under: window).compactMap(\.accessibilityLabel)
        let element = try XCTUnwrap(find(), "no element \"\(name)\" in \(shown)", file: file, line: line)
        XCTAssertTrue(element.accessibilityActivate(), "could not activate \"\(name)\"", file: file, line: line)
    }

    // A guest's mic opens the sign-in prompt over a list, and Log in opens auth on top. Closing auth
    // pops the list screen too (NAV-03), so the lists come back on top: like Android, which pops
    // to the lists, the list screen must not report itself on the way out.
    func testClosingSignInOpenedFromAListReportsTheListsAndNotTheList() async throws {
        let container = try makeContainer(screen: .lists)
        try hostApp(container)
        await waitForScreen(.shoppingList)
        await container.lists.confirmCreate(named: "Weekly")
        await waitForScreen(.shoppingItems)

        try await tap(String(localized: .voiceAdd))
        try await tap(AuthPromptContent.confirmTitle)
        await waitForScreen(.login)
        try await tap(String(localized: .close))

        await waitForScreen(.shoppingList)
        // Give a late report from the list screen time to land before checking the whole sequence.
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual([.shoppingList, .shoppingItems, .login, .shoppingList], screens)
    }

    // Forgot password is only reached by a tap on Login, so the auth sheet is hosted on its own,
    // already on that screen, with the tracker `RootView` hands to everything it shows.
    func testForgotPasswordReportsItself() async throws {
        let container = try makeContainer(screen: .lists)

        try host(AuthSheet(flow: AuthFlow(start: .forgotPassword, below: .lists)) { _ in }
            .environment(container)
            .environment(\.screenTracker, container.screenTracker))

        await waitForScreen(.forgotPassword)
    }
}
