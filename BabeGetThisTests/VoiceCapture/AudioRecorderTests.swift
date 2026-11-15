import AVFoundation
import XCTest
@testable import BabeGetThis

/// A fake recorder that writes a real (tiny) file, so deletion is observable on disk. No audio is recorded.
@MainActor
private final class FileWritingRecorder: VoiceRecording {
    var onEndedOnItsOwn: (@MainActor () -> Void)?
    let file: URL
    init(file: URL) { self.file = file }
    func start() async throws {}
    func stop() async throws -> URL {
        try Data("not audio".utf8).write(to: file)
        return file
    }
    func cancel() {}
}

@MainActor
final class AudioRecorderTests: XCTestCase {
    func testRecordingFileIsDeletedAfterUse() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        let transcriber = FakeVoiceTranscriber()
        transcriber.result = .success([TranscribedItem(name: "Milk")])
        // Default deleteFile: the real file removal the app uses.
        let vm = VoiceCaptureViewModel(recorder: FileWritingRecorder(file: file), transcriber: transcriber,
                                       analytics: NoopVoiceCaptureAnalytics())
        vm.setPersist { _ in .success("list-1") }

        await vm.startRecording().value
        await vm.stopRecording().value

        XCTAssertEqual(vm.state, .done)
        XCTAssertEqual(transcriber.calls, [file])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRecorderSettingsAreAAC16kMono() {
        let settings = AVVoiceRecorder.settings
        XCTAssertEqual(settings[AVFormatIDKey] as? Int, Int(kAudioFormatMPEG4AAC))
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 16_000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(AVVoiceRecorder.maxDuration, 30)
    }

    func testRecordingFileIsAnM4AInTheGivenDirectory() {
        let dir = URL(filePath: "/tmp/voice-test", directoryHint: .isDirectory)
        let url = AVVoiceRecorder.fileURL(in: dir, now: Date(timeIntervalSince1970: 1_700_000_000.5))
        XCTAssertEqual(url.lastPathComponent, "voice-1700000000500.m4a")
        XCTAssertEqual(url.pathExtension, "m4a")
        XCTAssertEqual(url.deletingLastPathComponent().path, dir.path)
    }

    func testCancelDeletesTheRecordingFile() throws {
        let file = AVVoiceRecorder.fileURL(in: FileManager.default.temporaryDirectory)
        try Data("not audio".utf8).write(to: file)
        let recorder = AVVoiceRecorder(tone: InstantTone())
        recorder.adoptOutputFileForTesting(file)

        recorder.cancel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    // record(forDuration: 30) stops by itself at the cap; the view model must hear about it,
    // or the sheet keeps saying "Listening" over a mic that's off.
    func testReachingTheThirtySecondCapEndsTheRecording() async throws {
        let file = AVVoiceRecorder.fileURL(in: FileManager.default.temporaryDirectory)
        let recorder = AVVoiceRecorder(tone: InstantTone(), interruptions: RecordingInterruptions(center: NotificationCenter()))
        var ends = 0
        recorder.onEndedOnItsOwn = { ends += 1 }
        recorder.adoptOutputFileForTesting(file)

        recorder.audioRecorderDidFinishRecording(try AVAudioRecorder(url: file, settings: AVVoiceRecorder.settings),
                                                 successfully: true)

        await voiceTestEventually { ends == 1 }
        XCTAssertEqual(ends, 1)
    }

    func testTheCapAfterCancelIsNotAnEnd() async throws {
        let file = AVVoiceRecorder.fileURL(in: FileManager.default.temporaryDirectory)
        let recorder = AVVoiceRecorder(tone: InstantTone(), interruptions: RecordingInterruptions(center: NotificationCenter()))
        var ends = 0
        recorder.onEndedOnItsOwn = { ends += 1 }
        recorder.adoptOutputFileForTesting(file)
        recorder.cancel()

        recorder.audioRecorderDidFinishRecording(try AVAudioRecorder(url: file, settings: AVVoiceRecorder.settings),
                                                 successfully: true)

        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(ends, 0)
    }

    /// The tone completion arrives on a background queue (AudioToolbox's own serial queue).
    /// Before the fix the resume closure was @MainActor-inferred and trapped here.
    func testStartToneCompletionOffTheMainQueueResumesPlay() async {
        let player = SystemStartTonePlayer { _, completion in
            DispatchQueue.global(qos: .userInitiated).async {
                XCTAssertFalse(Thread.isMainThread)
                completion()
            }
        }
        await player.play()
    }

    /// The real AudioToolbox path. Crashes (rather than fails) if the completion's isolation
    /// is wrong; skipped if the simulator never reports the sound finished.
    func testSystemStartToneCompletesWithoutTrapping() async throws {
        let finished = expectation(description: "tone finished")
        let task = Task { @MainActor in
            await SystemStartTonePlayer().play()
            finished.fulfill()
        }
        let result = await XCTWaiter().fulfillment(of: [finished], timeout: 5)
        if result == .timedOut {
            task.cancel()
            throw XCTSkip("The simulator did not report the system sound finishing.")
        }
    }
}

@MainActor
private struct InstantTone: StartTonePlaying {
    func play() async {}
}
