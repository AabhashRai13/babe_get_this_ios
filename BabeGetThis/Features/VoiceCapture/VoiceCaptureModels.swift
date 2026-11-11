import Foundation

/// Where the capture flow is. Mirrors Android's VoiceCaptureUiState.
enum VoiceCaptureState: Equatable, Sendable {
    case idle
    case needsPermission
    case recording
    case transcribing
    case saving
    case done
    case failed(String)
}

/// Bounded reason for a failed transcription. Never carries server text.
enum VoiceCaptureFailureReason: Equatable, Sendable {
    case nothingHeard
    case network
    case timeout
    case unauthorized
    case server
    case unknown

    init(_ error: VoiceError) {
        switch error {
        case .network: self = .network
        case .timeout: self = .timeout
        case .unauthorized: self = .unauthorized
        case .server: self = .server
        case .unknown: self = .unknown
        }
    }
}

/// The voice funnel events the view model reports.
enum VoiceCaptureEvent: Equatable, Sendable {
    case sheetOpened
    case recordingStarted
    case recordingFailed
    case recordingCancelled(elapsedMillis: Int)
    case transcriptionCompleted(latencyMillis: Int, itemCount: Int)
    case transcriptionFailed(reason: VoiceCaptureFailureReason, latencyMillis: Int)
    case itemsSaved(itemCount: Int)
}

@MainActor
protocol VoiceCaptureAnalytics {
    func track(_ event: VoiceCaptureEvent)
}

@MainActor
struct NoopVoiceCaptureAnalytics: VoiceCaptureAnalytics {
    func track(_ event: VoiceCaptureEvent) {}
}

/// Microphone recording behind a seam so the view model never touches real audio in tests.
@MainActor
protocol VoiceRecording: AnyObject {
    /// Plays the start tone, then opens the mic. Returns once the mic is live.
    func start() async throws
    /// Stops and returns the recorded file.
    func stop() async throws -> URL
    /// Releases the recorder and discards any file. Idempotent.
    func cancel()
}

@MainActor
protocol VoiceTranscribing {
    func transcribeAndParse(audioFile: URL) async throws -> [TranscribedItem]
}

extension TranscribeClient: VoiceTranscribing {}

extension TranscribedItem {
    /// Maps a transcribed item onto the add-item draft. Absent optionals become empty strings.
    func toItemDraft() -> ItemDraft {
        var draft = ItemDraft()
        draft.name = name
        draft.quantity = quantity ?? ""
        draft.categoryId = category
        draft.shop = shop ?? ""
        draft.note = note ?? ""
        return draft
    }
}
