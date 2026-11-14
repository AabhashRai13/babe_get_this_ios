import SwiftUI

/// "Share list live" (Android `ShareCodeDialog`): the list's code in large letter-spaced type,
/// the hint, "Copy" and "Done". Starts the share when it appears; a failure shows as a snackbar.
/// No share sheet on purpose (Android product decision 001): the user texts the code with
/// whatever app they already talk to their partner in.
struct ShareLiveSheet: View {
    @State private var viewModel: ShareLiveViewModel
    /// Closes the sheet ("Done").
    let onDone: () -> Void
    /// The session was lost before the share: close the sheet and ask the user to sign in.
    let onNeedsSignIn: () -> Void

    init(viewModel: ShareLiveViewModel, onDone: @escaping () -> Void, onNeedsSignIn: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onDone = onDone
        self.onNeedsSignIn = onNeedsSignIn
    }

    /// Android: `displaySmall` with a quarter of its size as letter spacing.
    private static let codeTracking: CGFloat = 9

    var body: some View {
        VStack(spacing: 12) {
            Text(ShareLiveCopy.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let code = viewModel.shareCode {
                Text(code)
                    .font(.largeTitle)
                    .tracking(Self.codeTracking)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(.top, 8)
                    .accessibilityIdentifier("shareLive.code")
                Text(ShareLiveCopy.hint)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            } else if viewModel.isSharing {
                ProgressView()
                    .padding(.vertical, 24)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Spacer()
                Button(ShareLiveCopy.done) {
                    viewModel.dismissShareCode()
                    onDone()
                }
                .accessibilityIdentifier("shareLive.done")
                if viewModel.shareCode != nil {
                    Button {
                        SystemHapticPlayer().play(.light)
                        viewModel.copyCode()
                    } label: {
                        Label(ShareLiveCopy.copy, systemImage: "doc.on.doc")
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("shareLive.copy")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.surface)
        .overlay(alignment: .bottom) {
            if let message = viewModel.errorMessage {
                Snackbar(message: message)
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: SnackbarDuration.short)
                        if !Task.isCancelled { viewModel.errorMessage = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.25), value: viewModel.errorMessage)
        .task { await viewModel.shareLive() }
        .onChange(of: viewModel.showsAuthPrompt) { _, shows in
            guard shows else { return }
            viewModel.dismissAuthPrompt()
            onNeedsSignIn()
        }
    }
}
