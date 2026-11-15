import Foundation

// The bridges from each feature's own analytics protocol to the app's event catalog
// (`AnalyticsEvent`). The features stay ignorant of telemetry; `AppContainer` hands these out.

/// Sends the Welcome choice as `welcome_choice`.
struct TrackingWelcomeAnalytics: WelcomeAnalytics {
    let analytics: any AnalyticsRepository

    func track(choice: WelcomeChoice) {
        analytics.track(.welcomeChoiceMade(choice))
    }
}

/// Sends sign-in and sign-up as `account_logged_in` and `account_registered`.
struct TrackingAuthAnalytics: LoginAnalytics, RegisterAnalytics {
    let analytics: any AnalyticsRepository

    func trackAccountLoggedIn() {
        analytics.track(.accountLoggedIn)
    }

    func trackAccountRegistered() {
        analytics.track(.accountRegistered)
    }
}

/// Sends the voice funnel (`voice_*` events).
@MainActor
struct TrackingVoiceCaptureAnalytics: VoiceCaptureAnalytics {
    let analytics: any AnalyticsRepository

    func track(_ event: VoiceCaptureEvent) {
        analytics.track(Self.analyticsEvent(for: event))
    }

    private static func analyticsEvent(for event: VoiceCaptureEvent) -> AnalyticsEvent {
        switch event {
        case .sheetOpened: .voiceSheetOpened
        case .recordingStarted: .voiceRecordingStarted
        case .recordingFailed: .voiceRecordingFailed
        case .recordingCancelled(let elapsedMillis): .voiceRecordingCancelled(elapsedMillis: Int64(elapsedMillis))
        case .transcriptionCompleted(let latencyMillis, let itemCount):
            .voiceTranscriptionCompleted(latencyMillis: Int64(latencyMillis), itemCount: itemCount)
        case .transcriptionFailed(let reason, let latencyMillis):
            .voiceTranscriptionFailed(reason: analyticsReason(for: reason), latencyMillis: Int64(latencyMillis))
        case .itemsSaved(let itemCount): .voiceItemsSaved(itemCount: itemCount)
        }
    }

    private static func analyticsReason(for reason: VoiceCaptureFailureReason) -> VoiceFailureReason {
        switch reason {
        case .nothingHeard: .nothingHeard
        case .network: .network
        case .timeout: .timeout
        case .server: .server
        // The analytics taxonomy has no "unauthorized"; Android reports an auth failure as unknown.
        case .unauthorized, .unknown: .unknown
        }
    }
}
