import SwiftUI

/// Create-method chooser (Android CreateListChooserSheet): two tonal tiles, Type and Voice.
struct CreateListChooserSheet: View {
    let onPickType: () -> Void
    let onPickVoice: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ChooserTile(systemImage: "pencil", label: "Type",
                        badge: AppColors.secondaryContainer, onBadge: AppColors.onSecondaryContainer,
                        identifier: "chooser.type", action: onPickType)
            ChooserTile(systemImage: "mic.fill", label: "Voice",
                        badge: AppColors.primaryContainer, onBadge: AppColors.onPrimaryContainer,
                        identifier: "chooser.voice", action: onPickVoice)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .presentationDetents([.height(190)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

private struct ChooserTile: View {
    let systemImage: String
    let label: String
    let badge: Color
    let onBadge: Color
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(onBadge)
                    .frame(width: 56, height: 56)
                    .background(badge, in: Circle())
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(AppColors.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        CreateListChooserSheet(onPickType: {}, onPickVoice: {})
    }
}
