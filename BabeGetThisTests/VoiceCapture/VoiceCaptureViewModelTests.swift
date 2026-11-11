import XCTest
@testable import BabeGetThis

@MainActor
final class VoiceCaptureViewModelTests: XCTestCase {
    private var recorder: FakeVoiceRecorder!
    private var transcriber: FakeVoiceTranscriber!
    private var analytics: RecordingVoiceAnalytics!
    private var deleted: [URL] = []
    private let drafts = [TranscribedItem(name: "Milk"), TranscribedItem(name: "Eggs")]

    override func setUp() async throws {
        recorder = FakeVoiceRecorder()
        transcriber = FakeVoiceTranscriber()
        analytics = RecordingVoiceAnalytics()
        deleted = []
    }

    private func makeViewModel() -> VoiceCaptureViewModel {
        VoiceCaptureViewModel(
            recorder: recorder,
            transcriber: transcriber,
            analytics: analytics,
            deleteFile: { [weak self] in self?.deleted.append($0) }
        )
    }

    private func recordAndStop(_ vm: VoiceCaptureViewModel) async {
        await vm.startRecording().value
        await vm.stopRecording().value
    }

    // MARK: permission gate

    func testStartsIdle() {
        XCTAssertEqual(makeViewModel().state, .idle)
    }

    func testDeniedPermissionParksInNeedsPermission() {
        let vm = makeViewModel()
        vm.onPermissionResult(granted: false)
        XCTAssertEqual(vm.state, .needsPermission)
    }

    func testGrantedPermissionReturnsToIdle() {
        let vm = makeViewModel()
        vm.onPermissionResult(granted: false)
        vm.onPermissionResult(granted: true)
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: recording

    func testStartRecordingOpensMicThenReportsRecording() async {
        let vm = makeViewModel()
        await vm.startRecording().value
        XCTAssertEqual(recorder.startCalls, 1)
        XCTAssertEqual(vm.state, .recording)
    }

    func testRecordingIsNotAnnouncedWhileCueToneIsStillPlaying() async {
        let gate = VoiceTestGate()
        recorder.startGate = gate
        let vm = makeViewModel()

        let task = vm.startRecording()
        await voiceTestEventually { self.recorder.startCalls == 1 }
        XCTAssertEqual(vm.state, .idle)

        await gate.open()
        await task.value
        XCTAssertEqual(vm.state, .recording)
    }

    func testMicThatWillNotOpenLandsInFailed() async {
        recorder.startError = VoiceTestFailure(text: "mic busy")
        let vm = makeViewModel()
        await vm.startRecording().value
        guard case .failed = vm.state else { return XCTFail("expected failed, got \(vm.state)") }
    }

    func testFailedStartReleasesRecorder() async {
        recorder.startError = VoiceTestFailure(text: "bad state")
        let vm = makeViewModel()
        await vm.startRecording().value
        XCTAssertEqual(recorder.cancelCalls, 1)
    }

    func testFailureMessageDoesNotLeakErrorText() async {
        recorder.startError = VoiceTestFailure(text: "/var/mobile/cache/voice.m4a busy")
        let vm = makeViewModel()
        await vm.startRecording().value
        guard case .failed(let message) = vm.state else { return XCTFail("expected failed") }
        XCTAssertFalse(message.contains("/var/"), "leaked internals: \(message)")
    }

    // MARK: stop / transcribe

    func testStopRecordingTranscribesAndPersists() async {
        transcriber.result = .success(drafts)
        let vm = makeViewModel()
        vm.setPersist { _ in .success("list-1") }
        await recordAndStop(vm)
        XCTAssertEqual(vm.state, .done)
    }

    func testStopRecordingWaitsForInFlightStartBeforeStopping() async {
        let gate = VoiceTestGate()
        recorder.startGate = gate
        transcriber.result = .success(drafts)
        let vm = makeViewModel()
        vm.setPersist { _ in .success("list-1") }

        vm.startRecording()
        let stopTask = vm.stopRecording()
        await voiceTestEventually { self.recorder.startCalls == 1 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(recorder.stopCalls, 0)

        await gate.open()
        await stopTask.value
        XCTAssertEqual(recorder.stopCalls, 1)
    }

    func testNothingUnderstoodReportsRetryableFailureNotEmptyList() async {
        transcriber.result = .success([])
        var persisted = false
        let vm = makeViewModel()
        vm.setPersist { _ in
            persisted = true
            return .success("list-1")
        }
        await recordAndStop(vm)
        XCTAssertEqual(vm.state, .failed("Didn't catch any items. Try again?"))
        XCTAssertFalse(persisted, "must never create an empty list")
    }

    func testTranscriptionErrorSurfacesItsMessage() async {
        transcriber.result = .failure(VoiceError.network())
        let vm = makeViewModel()
        await recordAndStop(vm)
        XCTAssertEqual(vm.state, .failed(VoiceError.network().message))
    }

    func testRecorderThatFailsToStopLandsInFailed() async {
        recorder.stopError = VoiceTestFailure(text: "nothing captured")
        let vm = makeViewModel()
        await recordAndStop(vm)
        XCTAssertEqual(vm.state, .failed("Couldn't finish that recording. Try again?"))
        XCTAssertEqual(recorder.cancelCalls, 1)
    }

    func testRecordingIsDeletedAfterSuccessfulUpload() async {
        transcriber.result = .success(drafts)
        let vm = makeViewModel()
        vm.setPersist { _ in .success("list-1") }
        await recordAndStop(vm)
        XCTAssertEqual(deleted, [recorder.stopResult])
    }

    func testRecordingIsDeletedEvenWhenTranscriptionFails() async {
        transcriber.result = .failure(VoiceError.server(code: 500))
        let vm = makeViewModel()
        await recordAndStop(vm)
        XCTAssertEqual(deleted, [recorder.stopResult])
    }

    func testTranscriberReceivesTheRecordedFile() async {
        transcriber.result = .success(drafts)
        let vm = makeViewModel()
        vm.setPersist { _ in .success("list-1") }
        await recordAndStop(vm)
        XCTAssertEqual(transcriber.calls, [recorder.stopResult])
    }

    // MARK: persist

    func testPersistReceivesTheParsedDrafts() async {
        transcriber.result = .success(drafts)
        var received: [ItemDraft]?
        let vm = makeViewModel()
        vm.setPersist { items in
            received = items
            return .success("list-1")
        }
        await recordAndStop(vm)
        XCTAssertEqual(received, drafts.map { $0.toItemDraft() })
    }

    func testPersistFailureSurfacesItsMessage() async {
        transcriber.result = .success(drafts)
        let vm = makeViewModel()
        vm.setPersist { _ in .failure(.unknown("Could not save.")) }
        await recordAndStop(vm)
        XCTAssertEqual(vm.state, .failed("Could not save."))
    }

    func testNoPersistClosureFailsLoudlyRatherThanDroppingTheList() async {
        transcriber.result = .success(drafts)
        let vm = makeViewModel()
        await recordAndStop(vm)
        XCTAssertEqual(vm.state, .failed("Something went wrong saving your list."))
    }

    func testSavingIsAnnouncedBeforePersistCompletes() async {
        let gate = VoiceTestGate()
        transcriber.result = .success(drafts)
        let vm = makeViewModel()
        vm.setPersist { _ in
            await gate.wait()
            return .success("list-1")
        }
        await vm.startRecording().value
        let stopTask = vm.stopRecording()
        await voiceTestEventually { vm.state == .saving }
        XCTAssertEqual(vm.state, .saving)

        await gate.open()
        await stopTask.value
        XCTAssertEqual(vm.state, .done)
    }

    // MARK: cancel

    func testCancelResetsToIdleAndReleasesRecorder() async {
        let vm = makeViewModel()
        await vm.startRecording().value
        vm.cancel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertGreaterThanOrEqual(recorder.cancelCalls, 1)
    }

    func testCancelAbortsInFlightTranscriptionBeforeItCanPersist() async {
        let gate = VoiceTestGate()
        transcriber.gate = gate
        transcriber.result = .success(drafts)
        var persisted = false
        let vm = makeViewModel()
        vm.setPersist { _ in
            persisted = true
            return .success("list-1")
        }
        await vm.startRecording().value
        let stopTask = vm.stopRecording()
        await voiceTestEventually { self.transcriber.calls.count == 1 }

        vm.cancel()
        await gate.open()
        await stopTask.value

        XCTAssertFalse(persisted, "a dismissed sheet must not persist anything")
        XCTAssertEqual(vm.state, .idle)
    }

    func testCancelDuringCueToneNeverOpensTheMic() async {
        let gate = VoiceTestGate()
        recorder.startGate = gate
        let vm = makeViewModel()
        let task = vm.startRecording()
        await voiceTestEventually { self.recorder.startCalls == 1 }

        vm.cancel()
        await gate.open()
        await task.value

        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(analytics.events, [])
    }

    func testCancelIsSafeFromIdle() {
        let vm = makeViewModel()
        vm.cancel()
        XCTAssertEqual(vm.state, .idle)
    }

    func testCancelAlsoClearsNeedsPermission() {
        let vm = makeViewModel()
        vm.onPermissionResult(granted: false)
        vm.cancel()
        XCTAssertEqual(vm.state, .idle)
    }

    func testStateTransitionsAreObservableInOrder() async {
        let transcribeGate = VoiceTestGate()
        let persistGate = VoiceTestGate()
        transcriber.gate = transcribeGate
        transcriber.result = .success(drafts)
        let vm = makeViewModel()
        vm.setPersist { _ in
            await persistGate.wait()
            return .success("list-1")
        }

        await vm.startRecording().value
        XCTAssertEqual(vm.state, .recording)

        let stopTask = vm.stopRecording()
        await voiceTestEventually { self.transcriber.calls.count == 1 }
        XCTAssertEqual(vm.state, .transcribing)

        await transcribeGate.open()
        await voiceTestEventually { vm.state == .saving }
        XCTAssertEqual(vm.state, .saving)

        await persistGate.open()
        await stopTask.value
        XCTAssertEqual(vm.state, .done)
    }

    // MARK: telemetry

    func testCompletedCaptureReportsFunnelInOrder() async {
        transcriber.result = .success(drafts)
        let vm = makeViewModel()
        vm.setPersist { _ in .success("list-1") }

        vm.onSheetOpened()
        await recordAndStop(vm)

        XCTAssertEqual(analytics.events.count, 4)
        XCTAssertEqual(analytics.events[0], .sheetOpened)
        XCTAssertEqual(analytics.events[1], .recordingStarted)
        guard case .transcriptionCompleted(_, let count) = analytics.events[2] else { return XCTFail("order: \(analytics.events)") }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(analytics.events[3], .itemsSaved(itemCount: 2))
    }

    func testResetAfterSuccessfulCaptureIsNotReportedAsAbandonment() async {
        transcriber.result = .success(drafts)
        let vm = makeViewModel()
        vm.setPersist { _ in .success("list-1") }
        await recordAndStop(vm)

        // What the sheet does to clear the stale Done state.
        vm.cancel()

        XCTAssertEqual(analytics.cancelledCount, 0)
    }

    func testWalkingAwayMidRecordingIsReportedAsAbandonment() async {
        let vm = makeViewModel()
        await vm.startRecording().value
        vm.cancel()
        XCTAssertEqual(analytics.cancelledCount, 1)
    }

    func testNothingUnderstoodIsReportedAsFailureNotZeroItemSuccess() async {
        transcriber.result = .success([])
        let vm = makeViewModel()
        await recordAndStop(vm)
        XCTAssertEqual(analytics.failureReasons, [.nothingHeard])
        XCTAssertEqual(analytics.completedCount, 0)
    }

    func testTranscriptionFailureReportsErrorTypeNeverItsMessage() async {
        transcriber.result = .failure(VoiceError.server(code: 500, message: "upstream whisper-v3 timeout at pod-4b"))
        let vm = makeViewModel()
        await recordAndStop(vm)
        XCTAssertEqual(analytics.failureReasons, [.server])
    }

    func testMicThatWillNotOpenIsReported() async {
        recorder.startError = VoiceTestFailure(text: "mic busy")
        let vm = makeViewModel()
        await vm.startRecording().value
        XCTAssertTrue(analytics.events.contains(.recordingFailed))
        // The mic never opened, so there is no recording to abandon.
        vm.cancel()
        XCTAssertEqual(analytics.cancelledCount, 0)
    }
}
