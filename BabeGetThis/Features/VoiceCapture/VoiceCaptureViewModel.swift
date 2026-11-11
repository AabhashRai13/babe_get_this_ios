import Foundation
import Observation

/// Orchestrates record -> transcribe -> persist. No review step: once items come back the
/// persist closure creates the list and the host navigates into it.
///
/// Only knows the recorder, the transcriber and a `persist` closure seeded by the sheet,
/// so it stays agnostic about shopping-list storage.
@MainActor
@Observable
final class VoiceCaptureViewModel {
    typealias Persist = @MainActor ([ItemDraft]) async -> Result<String, VoiceError>

    private(set) var state: VoiceCaptureState = .idle

    @ObservationIgnored private let recorder: VoiceRecording
    @ObservationIgnored private let transcriber: VoiceTranscribing
    @ObservationIgnored private let analytics: VoiceCaptureAnalytics
    @ObservationIgnored private let deleteFile: @MainActor (URL) -> Void
    @ObservationIgnored private var persist: Persist?
    /// In-flight start (tone + mic open). Stop waits for it; cancel aborts it.
    @ObservationIgnored private var recordTask: Task<Void, Never>?
    /// In-flight transcribe + persist, so cancel() means nothing lands.
    @ObservationIgnored private var transcribeTask: Task<Void, Never>?
    /// Set while a recording is live; tells a real abort from the sheet's post-success reset.
    @ObservationIgnored private var recordingStartedAt: Date?

    init(
        recorder: VoiceRecording,
        transcriber: VoiceTranscribing,
        analytics: VoiceCaptureAnalytics = NoopVoiceCaptureAnalytics(),
        deleteFile: @escaping @MainActor (URL) -> Void = { try? FileManager.default.removeItem(at: $0) }
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.analytics = analytics
        self.deleteFile = deleteFile
    }

    func setPersist(_ block: @escaping Persist) {
        persist = block
    }

    func onSheetOpened() {
        analytics.track(.sheetOpened)
    }

    func onPermissionResult(granted: Bool) {
        state = granted ? .idle : .needsPermission
    }

    @discardableResult
    func startRecording() -> Task<Void, Never> {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                // Recording is announced only once start() returns, i.e. the mic is live.
                try await recorder.start()
                if Task.isCancelled {
                    recorder.cancel()
                    return
                }
                recordingStartedAt = Date()
                state = .recording
                analytics.track(.recordingStarted)
            } catch is CancellationError {
                return
            } catch {
                recorder.cancel()
                recordingStartedAt = nil
                state = .failed("Couldn't start recording. Is the microphone in use?")
                analytics.track(.recordingFailed)
            }
        }
        recordTask = task
        return task
    }

    @discardableResult
    func stopRecording() -> Task<Void, Never> {
        let task = Task { [weak self] in
            guard let self else { return }
            state = .transcribing
            // Wait for start() (tone + mic open) so we never stop a recorder that doesn't exist yet.
            await recordTask?.value
            if Task.isCancelled { return }
            recordingStartedAt = nil
            do {
                let file = try await recorder.stop()
                defer { deleteFile(file) }
                await transcribeAndPersist(file)
            } catch is CancellationError {
                return
            } catch {
                recorder.cancel()
                state = .failed("Couldn't finish that recording. Try again?")
            }
        }
        transcribeTask = task
        return task
    }

    private func transcribeAndPersist(_ file: URL) async {
        let startedAt = Date()
        func latency() -> Int { Int(Date().timeIntervalSince(startedAt) * 1000) }
        do {
            let items = try await transcriber.transcribeAndParse(audioFile: file)
            if Task.isCancelled { return }
            if items.isEmpty {
                state = .failed("Didn't catch any items. Try again?")
                // A failure from the user's side, not a zero-item success.
                analytics.track(.transcriptionFailed(reason: .nothingHeard, latencyMillis: latency()))
                return
            }
            analytics.track(.transcriptionCompleted(latencyMillis: latency(), itemCount: items.count))
            await persistDrafts(items.map { $0.toItemDraft() })
        } catch is CancellationError {
            return
        } catch {
            let voiceError = VoiceError.fromThrown(error)
            state = .failed(voiceError.message)
            // The error category only, never its message (it can carry server text).
            analytics.track(.transcriptionFailed(reason: VoiceCaptureFailureReason(voiceError), latencyMillis: latency()))
        }
    }

    private func persistDrafts(_ drafts: [ItemDraft]) async {
        guard let persist else {
            state = .failed("Something went wrong saving your list.")
            return
        }
        state = .saving
        let result = await persist(drafts)
        if Task.isCancelled { return }
        switch result {
        case .success:
            state = .done
            analytics.track(.itemsSaved(itemCount: drafts.count))
        case .failure(let error):
            state = .failed(error.message)
        }
    }

    /// Aborts whatever is in flight and resets. Safe from any state.
    func cancel() {
        if let startedAt = recordingStartedAt {
            analytics.track(.recordingCancelled(elapsedMillis: Int(Date().timeIntervalSince(startedAt) * 1000)))
            recordingStartedAt = nil
        }
        recordTask?.cancel()
        recordTask = nil
        transcribeTask?.cancel()
        transcribeTask = nil
        recorder.cancel()
        state = .idle
    }
}
