import Foundation
@testable import BabeGetThis

/// One-shot gate: waiters suspend until `open()`. Deliberately ignores task cancellation,
/// so tests can prove the view model itself refuses to persist after cancel().
actor VoiceTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

struct VoiceTestFailure: Error { let text: String }

@MainActor
final class FakeVoiceRecorder: VoiceRecording {
    var startGate: VoiceTestGate?
    var startError: Error?
    var stopError: Error?
    var stopResult = URL(fileURLWithPath: "/tmp/voice-test.m4a")
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var cancelCalls = 0

    func start() async throws {
        startCalls += 1
        if let startGate { await startGate.wait() }
        try Task.checkCancellation()
        if let startError { throw startError }
    }

    func stop() async throws -> URL {
        stopCalls += 1
        if let stopError { throw stopError }
        return stopResult
    }

    func cancel() { cancelCalls += 1 }
}

@MainActor
final class FakeVoiceTranscriber: VoiceTranscribing {
    var result: Result<[TranscribedItem], Error> = .success([])
    var gate: VoiceTestGate?
    private(set) var calls: [URL] = []

    func transcribeAndParse(audioFile: URL) async throws -> [TranscribedItem] {
        calls.append(audioFile)
        if let gate { await gate.wait() }
        return try result.get()
    }
}

@MainActor
final class RecordingVoiceAnalytics: VoiceCaptureAnalytics {
    private(set) var events: [VoiceCaptureEvent] = []
    func track(_ event: VoiceCaptureEvent) { events.append(event) }

    var cancelledCount: Int {
        events.filter { if case .recordingCancelled = $0 { true } else { false } }.count
    }
    var completedCount: Int {
        events.filter { if case .transcriptionCompleted = $0 { true } else { false } }.count
    }
    var failureReasons: [VoiceCaptureFailureReason] {
        events.compactMap { if case .transcriptionFailed(let reason, _) = $0 { reason } else { nil } }
    }
}

/// Lets the main actor run queued work until `condition` holds (bounded).
@MainActor
func voiceTestEventually(_ condition: () -> Bool) async {
    for _ in 0..<500 {
        if condition() { return }
        await Task.yield()
    }
}
