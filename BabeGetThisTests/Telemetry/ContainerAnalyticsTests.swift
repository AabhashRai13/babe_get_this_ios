import XCTest
@testable import BabeGetThis

/// TEL-03 at the composition root: the events the auth and voice view models already emit reach
/// the app's analytics. Nothing here configures Firebase or opens a Supabase client.
@MainActor
final class ContainerAnalyticsTests: XCTestCase {
    private var analytics: RecordingAnalytics!
    private var container: AppContainer!

    override func setUp() async throws {
        try await super.setUp()
        analytics = RecordingAnalytics()
        container = AppContainer(
            config: .preview, authState: AuthStateManager(tokenStore: InMemoryTokenStore()),
            database: try AppDatabase.inMemory(), ownership: FakeListOwnershipStore(),
            telemetry: TelemetryVendors(analytics: analytics, crashReporter: RecordingCrashReporter()),
            telemetryConsentStore: InMemoryTelemetryConsentStore())
    }

    func testTheVoiceSheetsViewModelReportsToAnalytics() {
        let viewModel = container.makeVoiceCaptureViewModel()

        viewModel.onSheetOpened()

        XCTAssertEqual([.voiceSheetOpened], analytics.events)
    }

    // `makeLoginViewModel()` and `makeRegisterViewModel()` pass this (neither view model has a
    // silent default, so a call site can't leave it out); building them here would open a
    // Supabase client.
    func testSignInAndSignUpReportToAnalytics() {
        container.authAnalytics.trackAccountLoggedIn()
        container.authAnalytics.trackAccountRegistered()

        XCTAssertEqual([.accountLoggedIn, .accountRegistered], analytics.events)
    }

    func testEveryVoiceEventKeepsItsMeaning() {
        let voice = TrackingVoiceCaptureAnalytics(analytics: analytics)

        voice.track(.sheetOpened)
        voice.track(.recordingStarted)
        voice.track(.recordingFailed)
        voice.track(.recordingCancelled(elapsedMillis: 1_500))
        voice.track(.transcriptionCompleted(latencyMillis: 900, itemCount: 3))
        voice.track(.transcriptionFailed(reason: .timeout, latencyMillis: 30_000))
        voice.track(.itemsSaved(itemCount: 3))

        XCTAssertEqual([
            .voiceSheetOpened,
            .voiceRecordingStarted,
            .voiceRecordingFailed,
            .voiceRecordingCancelled(elapsedMillis: 1_500),
            .voiceTranscriptionCompleted(latencyMillis: 900, itemCount: 3),
            .voiceTranscriptionFailed(reason: .timeout, latencyMillis: 30_000),
            .voiceItemsSaved(itemCount: 3),
        ], analytics.events)
    }

    func testEveryVoiceFailureReasonHasAnAnalyticsReason() {
        let voice = TrackingVoiceCaptureAnalytics(analytics: analytics)
        let reasons: [VoiceCaptureFailureReason] = [.nothingHeard, .network, .timeout, .unauthorized, .server, .unknown]

        for reason in reasons {
            voice.track(.transcriptionFailed(reason: reason, latencyMillis: 1))
        }

        let sent: [VoiceFailureReason] = analytics.events.compactMap { event in
            guard case .voiceTranscriptionFailed(let reason, _) = event else { return nil }
            return reason
        }
        // The analytics taxonomy has no "unauthorized"; like Android, an auth failure is unknown.
        XCTAssertEqual([.nothingHeard, .network, .timeout, .unknown, .server, .unknown], sent)
    }
}
