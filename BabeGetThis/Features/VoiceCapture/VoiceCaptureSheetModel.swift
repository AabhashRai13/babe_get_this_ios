import AVFoundation
import Observation
import UIKit

/// The system's record permission (`AVAudioApplication.recordPermission`).
enum MicrophonePermissionStatus: Equatable, Sendable {
    /// Never asked: `request()` shows the system prompt.
    case undetermined
    /// Refused. iOS never prompts again; only Settings can change it.
    case denied
    case granted
}

/// Microphone permission behind a seam so tests never touch the system prompt.
@MainActor
protocol MicrophonePermissionProviding: AnyObject {
    var status: MicrophonePermissionStatus { get }
    /// Prompts only while `.undetermined`; afterwards it returns the stored answer at once.
    func request() async -> Bool
}

@MainActor
final class SystemMicrophonePermission: MicrophonePermissionProviding {
    var status: MicrophonePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }

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
    nonisolated static let lines = ["Listening to your list…", "Sorting your items…", "Almost there…"]
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
    static let permissionMessage = "Microphone access is needed to capture your list."

    let viewModel: VoiceCaptureViewModel
    /// Last known permission, refreshed on open, after asking and when the app comes back.
    private(set) var permissionStatus: MicrophonePermissionStatus
    @ObservationIgnored private let permission: MicrophonePermissionProviding
    @ObservationIgnored private let onDismiss: @MainActor () -> Void
    @ObservationIgnored private let onSwitchToType: @MainActor () -> Void
    @ObservationIgnored private let openSettings: @MainActor () -> Void
    /// The host has already been told the sheet is closing (success or "Type instead").
    @ObservationIgnored private var closeHandled = false

    init(
        viewModel: VoiceCaptureViewModel,
        permission: MicrophonePermissionProviding,
        onDismiss: @escaping @MainActor () -> Void,
        onSwitchToType: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void = VoiceCaptureSheetModel.openAppSettings
    ) {
        self.viewModel = viewModel
        self.permission = permission
        self.permissionStatus = permission.status
        self.onDismiss = onDismiss
        self.onSwitchToType = onSwitchToType
        self.openSettings = openSettings
    }

    /// The app's page in Settings, where a denied microphone can be turned back on.
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    var content: VoiceCaptureSheetContent { Self.content(for: viewModel.state, permission: permissionStatus) }

    static func content(
        for state: VoiceCaptureState,
        permission: MicrophonePermissionStatus = .undetermined
    ) -> VoiceCaptureSheetContent {
        switch state {
        case .idle: .idle
        case .needsPermission:
            // Once denied, iOS won't prompt again, so the button goes to Settings instead.
            .needsPermission(
                message: permissionMessage,
                buttonTitle: permission == .denied ? "Open Settings" : "Allow microphone"
            )
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
        closeHandled = false
        viewModel.onSheetOpened()
        viewModel.setPersist(persist)
        permissionStatus = permission.status
        if permissionStatus == .granted {
            viewModel.startRecording()
        } else {
            await requestAndStart()
        }
    }

    /// "Allow microphone" asks the system; after a denial the same button opens Settings.
    func allowMicrophoneTapped() async {
        permissionStatus = permission.status
        if permissionStatus == .denied {
            openSettings()
        } else {
            await requestAndStart()
        }
    }

    /// The app came back to the foreground, possibly from Settings: if the microphone is now
    /// allowed while the sheet is waiting for it, start recording.
    func sceneBecameActive() {
        permissionStatus = permission.status
        guard viewModel.state == .needsPermission, permissionStatus == .granted else { return }
        viewModel.onPermissionResult(granted: true)
        viewModel.startRecording()
    }

    private func requestAndStart() async {
        let granted = await permission.request()
        permissionStatus = permission.status
        viewModel.onPermissionResult(granted: granted)
        if granted { viewModel.startRecording() }
    }

    func stopTapped() { viewModel.stopRecording() }

    func retryTapped() { viewModel.startRecording() }

    func typeInsteadTapped() {
        closeHandled = true
        viewModel.cancel()
        onSwitchToType()
    }

    /// The sheet left the screen: swipe-down, or the host closing it. Like Android's
    /// `onDismissRequest`, cancels and tells the host, unless the host already knows because
    /// the flow finished or switched to typing.
    func sheetDisappeared() {
        viewModel.cancel()
        guard !closeHandled else { return }
        closeHandled = true
        onDismiss()
    }

    /// Call whenever the view model state changes. On success the sheet closes, then the view
    /// model resets to idle so reopening records immediately instead of auto-dismissing on a
    /// stale Done.
    func stateChanged() {
        guard viewModel.state == .done else { return }
        closeHandled = true
        onDismiss()
        viewModel.cancel()
    }
}

extension VoiceCaptureSheetContent {
    /// What VoiceOver should hear when the sheet switches to this content in place: the text
    /// that appeared, so a failure or a permission request is never silent.
    var announcement: String? {
        switch self {
        case .idle: nil
        case .needsPermission(let message, _): message
        case .recording: "Listening…"
        case .transcribing: VoiceTranscribingCopy.lines[0]
        case .loading(let label): label
        case .failed(let message, _, _): message
        }
    }
}
