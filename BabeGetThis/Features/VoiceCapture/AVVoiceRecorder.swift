import AVFoundation
import AudioToolbox
import Foundation

/// Plays the cue that tells the user the mic is about to open.
@MainActor
protocol StartTonePlaying {
    /// Returns when the tone has finished (or immediately if it cannot play).
    func play() async
}

/// System "begin recording" sound; recording still works silently if it can't play.
@MainActor
struct SystemStartTonePlayer: StartTonePlaying {
    /// Plays a system sound and calls the completion when it ends, on any thread.
    typealias PlaySound = @Sendable (SystemSoundID, @escaping @Sendable () -> Void) -> Void

    static let soundID: SystemSoundID = 1113

    /// AudioToolbox issues the completion on its own serial queue, never main. The closure
    /// must be @Sendable (nonisolated): a @MainActor-inferred closure traps there in Swift 6.
    nonisolated static let systemPlaySound: PlaySound = { soundID, completion in
        AudioServicesPlaySystemSoundWithCompletion(soundID) { @Sendable in
            completion()
        }
    }

    private let playSound: PlaySound

    init(playSound: @escaping PlaySound = SystemStartTonePlayer.systemPlaySound) {
        self.playSound = playSound
    }

    func play() async {
        let playSound = playSound
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playSound(Self.soundID) { @Sendable in
                continuation.resume()
            }
        }
    }
}

/// AVAudioRecorder writing .m4a AAC 16 kHz mono, capped at 30 s.
@MainActor
final class AVVoiceRecorder: VoiceRecording {
    static let maxDuration: TimeInterval = 30
    static let sampleRate: Double = 16_000

    static var settings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
    }

    /// Where a recording started at `now` is written: `voice-<epoch ms>.m4a`.
    static func fileURL(in directory: URL, now: Date = Date()) -> URL {
        directory.appending(path: "voice-\(Int(now.timeIntervalSince1970 * 1000)).m4a")
    }

    private let tone: StartTonePlaying
    private let directory: URL
    private var recorder: AVAudioRecorder?
    private var outputFile: URL?

    /// Test seam: adopts an existing file as the current recording without opening the mic.
    func adoptOutputFileForTesting(_ file: URL) {
        outputFile = file
    }

    init(tone: StartTonePlaying = SystemStartTonePlayer(), directory: URL = FileManager.default.temporaryDirectory) {
        self.tone = tone
        self.directory = directory
    }

    func start() async throws {
        // Play the cue and wait for it to finish before opening the mic,
        // so the recording never contains our own sound.
        await tone.play()
        try Task.checkCancellation()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let file = Self.fileURL(in: directory)
        outputFile = file
        let newRecorder = try AVAudioRecorder(url: file, settings: Self.settings)
        recorder = newRecorder
        guard newRecorder.prepareToRecord(), newRecorder.record(forDuration: Self.maxDuration) else {
            throw VoiceError.unknown("Couldn't open the microphone.")
        }
    }

    func stop() async throws -> URL {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let file = outputFile else { throw VoiceError.unknown("No recording in progress.") }
        outputFile = nil
        return file
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let file = outputFile { try? FileManager.default.removeItem(at: file) }
        outputFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
