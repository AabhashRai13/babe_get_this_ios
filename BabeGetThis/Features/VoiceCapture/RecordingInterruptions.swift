import AVFoundation
import UIKit

/// Tells the recorder when iOS takes the microphone away mid-recording: a call, Siri or an
/// alarm (an audio session interruption), a media services reset, or the app leaving the
/// foreground (it has no background audio mode, so iOS stops the mic). Watches only between
/// `start` and `stop`.
@MainActor
final class RecordingInterruptions {
    private let center: NotificationCenter
    private var observers: [any NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    func start(_ onEnded: @escaping @MainActor @Sendable () -> Void) {
        stop()
        let interruptionBegan: @Sendable (Notification) -> Void = { note in
            // Only the start of one: its end is not a second loss of the mic.
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            guard type == .began else { return }
            MainActor.assumeIsolated { onEnded() }
        }
        let ended: @Sendable (Notification) -> Void = { _ in MainActor.assumeIsolated { onEnded() } }
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main,
                               using: interruptionBegan),
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main,
                               using: ended),
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main,
                               using: ended),
        ]
    }

    func stop() {
        observers.forEach(center.removeObserver)
        observers = []
    }
}
