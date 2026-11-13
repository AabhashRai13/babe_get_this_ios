import SwiftUI

/// Sheet that runs the whole voice-capture flow. The host supplies `persist` (names and creates
/// the list) and reacts to `onDismiss` / `onSwitchToType`. Entry points are wired elsewhere.
struct VoiceCaptureSheet: View {
    @State private var model: VoiceCaptureSheetModel
    private let persist: VoiceCaptureViewModel.Persist

    init(
        viewModel: VoiceCaptureViewModel,
        permission: MicrophonePermissionProviding = SystemMicrophonePermission(),
        persist: @escaping VoiceCaptureViewModel.Persist,
        onDismiss: @escaping @MainActor () -> Void,
        onSwitchToType: @escaping @MainActor () -> Void
    ) {
        _model = State(initialValue: VoiceCaptureSheetModel(
            viewModel: viewModel,
            permission: permission,
            onDismiss: onDismiss,
            onSwitchToType: onSwitchToType
        ))
        self.persist = persist
    }

    var body: some View {
        VStack(spacing: 0) {
            switch model.content {
            case .idle:
                ProgressView().padding(.vertical, 24)
            case let .needsPermission(message, buttonTitle):
                messageBlock(message)
                Button(buttonTitle) { Task { await model.allowMicrophoneTapped() } }
                    .buttonStyle(PrimaryButtonStyle())
            case .recording:
                RecordingContent(onStop: model.stopTapped)
            case .transcribing:
                TranscribingContent()
            case .loading(let label):
                ProgressView().padding(.top, 16)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.vertical, 16)
            case let .failed(message, retryTitle, typeInsteadTitle):
                messageBlock(message)
                Button(retryTitle, action: model.retryTapped)
                    .buttonStyle(PrimaryButtonStyle())
                Button(typeInsteadTitle, action: model.typeInsteadTapped)
                    .buttonStyle(OutlinedButtonStyle())
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppMetrics.welcomePadding)
        .padding(.bottom, 32)
        .padding(.top, 16)
        .background(AppColors.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task { await model.onAppear(persist: persist) }
        .onChange(of: model.viewModel.state) { _, _ in model.stateChanged() }
        .onDisappear { model.viewModel.cancel() }
    }

    private func messageBlock(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.top, 16)
            .padding(.bottom, 20)
    }
}

private struct RecordingContent: View {
    let onStop: () -> Void
    @State private var startedAt = Date()

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(AppColors.primary)
                .padding(.vertical, 24)
            // Timer is view-local so the view model isn't updated every tick.
            TimelineView(.periodic(from: startedAt, by: 0.2)) { context in
                let total = Int(context.date.timeIntervalSince(startedAt))
                Text(String(format: "%d:%02d", total / 60, total % 60))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary)
            }
            Text("Listening…")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
            Button(action: onStop) {
                Label("Stop", systemImage: "xmark")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 20)
        }
    }
}

private struct TranscribingContent: View {
    @State private var copy = VoiceTranscribingCopy()

    var body: some View {
        VStack(spacing: 20) {
            ProgressView().padding(.top, 20)
            Text(copy.line)
                .id(copy.line)
                .transition(.opacity)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
        .animation(.easeInOut, value: copy.line)
        .padding(.bottom, 16)
        .task { await copy.run() }
    }
}
