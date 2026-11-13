import AVFoundation
import Observation

/// Microphone permission behind a seam so tests never touch the system prompt.
@MainActor
protocol MicrophonePermissionProviding: AnyObject {
    var isGranted: Bool { get }
    func request() async -> Bool
}

@MainActor
final class SystemMicrophonePermission: MicrophonePermissionProviding {
    var isGranted: Bool { AVAudioApplication.shared.recordPermission == .granted }

    func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

/// What the sheet shows. Equatable so tests can assert the exact copy.
enum VoiceCaptureSheetContent: Equatable {
    case idle
    case needsPermission(message: String, buttonTitle: String)
    case recording
    case transcribing
    case loading(label: String)
    case failed(message: String, retryTitle: String, typeInsteadTitle: String)
}

/// The reassurance line under the transcribing waveform. Advances on a timer and HOLDS on the
/// last line; it never loops back, because cycling reads as "stuck".
@MainActor
@Observable
final class VoiceTranscribingCopy {
    static let lines = ["Listening to your list…", "Sorting your items…", "Almost there…"]
    static let interval: Duration = .milliseconds(2500)

    private(set) var index = 0
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void

    init(sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    var line: String { Self.lines[index] }

    func run() async {
        while index < Self.lines.count - 1 {
            await sleep(Self.interval)
            if Task.isCancelled { return }
            index += 1
        }
    }
}

/// View state for `VoiceCaptureSheet`: permission, auto-start and dismissal rules around
/// `VoiceCaptureViewModel`. Port of Android's VoiceCaptureSheet.kt logic.
@MainActor
@Observable
final class VoiceCaptureSheetModel {
    let viewModel: VoiceCaptureViewModel
    @ObservationIgnored private let permission: MicrophonePermissionProviding
    @ObservationIgnored private let onDismiss: @MainActor () -> Void
    @ObservationIgnored private let onSwitchToType: @MainActor () -> Void

    init(
        viewModel: VoiceCaptureViewModel,
        permission: MicrophonePermissionProviding,
        onDismiss: @escaping @MainActor () -> Void,
        onSwitchToType: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.permission = permission
        self.onDismiss = onDismiss
        self.onSwitchToType = onSwitchToType
    }

    var content: VoiceCaptureSheetContent { Self.content(for: viewModel.state) }

    static func content(for state: VoiceCaptureState) -> VoiceCaptureSheetContent {
        switch state {
        case .idle: .idle
        case .needsPermission:
            .needsPermission(message: "Microphone access is needed to capture your list.", buttonTitle: "Allow microphone")
        case .recording: .recording
        case .transcribing: .transcribing
        case .saving: .loading(label: "Saving your list…")
        case .done: .loading(label: "Done!")
        case .failed(let message):
            .failed(message: message, retryTitle: "Try again", typeInsteadTitle: "Type instead")
        }
    }

    /// Runs once when the sheet opens: seed persist, then record or ask for the microphone.
    func onAppear(persist: @escaping VoiceCaptureViewModel.Persist) async {
        viewModel.onSheetOpened()
        viewModel.setPersist(persist)
        if permission.isGranted {
            viewModel.startRecording()
        } else {
            await requestAndStart()
        }
    }

    func allowMicrophoneTapped() async {
        await requestAndStart()
    }

    private func requestAndStart() async {
        let granted = await permission.request()
        viewModel.onPermissionResult(granted: granted)
        if granted { viewModel.startRecording() }
    }

    func stopTapped() { viewModel.stopRecording() }

    func retryTapped() { viewModel.startRecording() }

    func typeInsteadTapped() {
        viewModel.cancel()
        onSwitchToType()
    }

    /// Swipe-down or system dismissal.
    func sheetDismissed() {
        viewModel.cancel()
        onDismiss()
    }

    /// Call whenever the view model state changes. On success the sheet closes, then the view
    /// model resets to idle so reopening records immediately instead of auto-dismissing on a
    /// stale Done.
    func stateChanged() {
        guard viewModel.state == .done else { return }
        onDismiss()
        viewModel.cancel()
    }
}
