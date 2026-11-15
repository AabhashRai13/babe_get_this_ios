import AVFoundation
import UIKit
import XCTest
@testable import BabeGetThis

/// iOS taking the microphone away mid-recording (VOICE-02): the recorder must hear about it.
@MainActor
final class RecordingInterruptionsTests: XCTestCase {
    private let center = NotificationCenter()
    private var ends = 0
    private var watch: RecordingInterruptions!

    override func setUp() async throws {
        ends = 0
        watch = RecordingInterruptions(center: center)
        watch.start { [weak self] in self?.ends += 1 }
    }

    override func tearDown() async throws {
        watch.stop()
    }

    private func postInterruption(_ type: AVAudioSession.InterruptionType) {
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue])
    }

    /// Lets any queued main-queue notification blocks run before checking nothing happened.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    func testACallOrSiriTakingTheMicEndsTheRecording() async {
        postInterruption(.began)

        await voiceTestEventually { self.ends == 1 }
        XCTAssertEqual(ends, 1)
    }

    func testTheInterruptionEndingIsNotAnEnd() async {
        postInterruption(.ended)

        await settle()
        XCTAssertEqual(ends, 0)
    }

    func testAMediaServicesResetEndsTheRecording() async {
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)

        await voiceTestEventually { self.ends == 1 }
        XCTAssertEqual(ends, 1)
    }

    // The app has no background audio mode, so iOS stops the mic when it leaves the foreground.
    func testLeavingTheForegroundEndsTheRecording() async {
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        await voiceTestEventually { self.ends == 1 }
        XCTAssertEqual(ends, 1)
    }

    func testNothingIsReportedOnceStopped() async {
        watch.stop()

        postInterruption(.began)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        await settle()
        XCTAssertEqual(ends, 0)
    }
}
