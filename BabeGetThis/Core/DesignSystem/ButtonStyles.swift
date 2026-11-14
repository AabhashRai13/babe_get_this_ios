import SwiftUI

/// Filled, full-width, 56 pt tall: Android `Button` on Welcome / auth screens.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppColors.onPrimary)
            .frame(maxWidth: .infinity, minHeight: AppMetrics.buttonHeight)
            .background(AppColors.primary.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// Outlined, full-width, 56 pt tall: Android `OutlinedButton`.
struct OutlinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppColors.primary)
            .frame(maxWidth: .infinity, minHeight: AppMetrics.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous)
                    .strokeBorder(AppColors.outline, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Tonal floating action button: Android `ExtendedFloatingActionButton` ("Create list").
struct TonalFABStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppColors.onPrimaryContainer)
            .padding(.horizontal, 20)
            .frame(minHeight: AppMetrics.buttonHeight)
            .background(AppColors.primaryContainer,
                        in: RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous))
            .shadow(color: AppColors.shadow.opacity(0.12), radius: AppMetrics.fabShadowRadius, y: AppMetrics.fabShadowY)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
