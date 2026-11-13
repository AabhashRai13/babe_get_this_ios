import SwiftUI

/// Bottom snackbar (Material `Snackbar`): a short message, optionally with one action.
/// Inverse colours, so it reads over any screen in light and dark mode.
struct Snackbar: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var lineLimit = 2

    var body: some View {
        HStack {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColors.surface)
                .lineLimit(lineLimit)
                .padding(.vertical, 12)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primaryContainer)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(AppColors.textPrimary, in: RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous))
        .padding(.horizontal, AppMetrics.screenPadding)
        .accessibilityElement(children: .contain)
    }
}

/// How long a message-only snackbar stays up (Compose `SnackbarDuration.Short`).
enum SnackbarDuration {
    static let short: Duration = .seconds(4)
}
