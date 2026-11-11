import AVFoundation
import XCTest
@testable import BabeGetThis

/// A fake recorder that writes a real (tiny) file, so deletion is observable on disk. No audio is recorded.
@MainActor
private final class FileWritingRecorder: VoiceRecording {
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
        let vm = VoiceCaptureViewModel(recorder: FileWritingRecorder(file: file), transcriber: transcriber)
        vm.setPersist { _ in .success("list-1") }

        await vm.startRecording().value
        await vm.stopRecording().value

        XCTAssertEqual(vm.state, .done)
        XCTAssertEqual(transcriber.calls, [file])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRecorderSettingsAreAAC16kMono() {
        let settings = AVVoiceRecorder.settings
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 16_000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(AVVoiceRecorder.maxDuration, 30)
    }
}
