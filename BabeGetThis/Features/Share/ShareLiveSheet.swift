import SwiftUI

/// "Share list live" (Android `ShareCodeDialog`): the list's code in large letter-spaced type,
/// the hint, "Copy" and "Done". Shown only once the share has produced a code; a failed share
/// never opens it (its message goes to the detail screen's snackbar).
/// No share sheet on purpose (Android product decision 001): the user texts the code with
/// whatever app they already talk to their partner in.
struct ShareLiveSheet: View {
    let viewModel: ShareLiveViewModel
    /// Closes the sheet ("Done").
    let onDone: () -> Void

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
                        // Android shows no in-app feedback either (the system shows its own
                        // "copied" overlay); a light haptic confirms the tap.
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
    }
}
