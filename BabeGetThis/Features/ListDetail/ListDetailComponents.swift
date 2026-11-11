import SwiftUI

/// "3 of 7 picked up", percentage badge and progress bar (Android `ProgressCard`).
struct ProgressCardView: View {
    let total: Int
    let pickedUp: Int

    private var progress: Double { total == 0 ? 0 : Double(pickedUp) / Double(total) }
    private var allDone: Bool { total > 0 && pickedUp == total }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    if allDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(AppColors.onPrimaryContainer)
                    }
                    Text(allDone ? "All done!" : "\(pickedUp) of \(total) picked up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(allDone ? AppColors.onPrimaryContainer : AppColors.textPrimary)
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(allDone ? AppColors.onPrimary : AppColors.onPrimaryContainer)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(allDone ? AppColors.primary : AppColors.primaryContainer,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.surfaceContainerHighest)
                    Capsule().fill(AppColors.primary)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 8)
            .animation(.easeOut(duration: 0.25), value: progress)
        }
        .padding(AppMetrics.screenPadding)
        .background(allDone ? AppColors.primaryContainer : AppColors.surfaceContainerLow,
                    in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
        .overlay {
            if !allDone {
                RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                    .strokeBorder(AppColors.outline.opacity(0.3), lineWidth: 0.5)
            }
        }
        .shadow(color: AppColors.shadow.opacity(0.08), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
    }
}

/// "ACTIVE ITEMS" / "COMPLETED" heading with an optional count pill.
struct SectionHeaderView: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(AppColors.primary).frame(width: 6, height: 6)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.primary)
            Spacer()
            if let count {
                Text(count == 1 ? "1 Item" : "\(count) Items")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColors.onPrimaryContainer)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(AppColors.primaryContainer, in: Capsule())
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Shop heading (pin icon, name, rule) or the lighter category heading beneath it.
struct GroupHeaderView: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(AppColors.primary)
            }
            Text(title)
                .font(systemImage == nil ? .subheadline.weight(.medium) : .headline)
                .foregroundStyle(systemImage == nil ? AppColors.textSecondary : AppColors.primary)
            Rectangle().fill(AppColors.outline.opacity(0.3)).frame(height: 0.5)
        }
        .padding(.leading, systemImage == nil ? 28 : 0)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One item: tick circle, name, italic note, quantity and category chips (Android `ShoppingItemCard`).
struct ItemCardView: View {
    let item: ShoppingItem
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(item.isPickedUp ? AppColors.primary : AppColors.surface)
                    if item.isPickedUp {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(AppColors.onPrimary)
                    } else {
                        Circle().strokeBorder(AppColors.outline, lineWidth: 1)
                    }
                }
                .frame(width: 30, height: 30)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -7)
            .accessibilityLabel(item.isPickedUp ? "Mark \(item.name) as not picked up" : "Mark \(item.name) as picked up")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(item.isPickedUp ? .regular : .medium))
                    .strikethrough(item.isPickedUp)
                    .foregroundStyle(AppColors.textPrimary.opacity(item.isPickedUp ? 0.45 : 1))
                    .lineLimit(1)
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote.italic())
                        .foregroundStyle(AppColors.textSecondary.opacity(item.isPickedUp ? 0.5 : 1))
                        .lineLimit(2)
                }
                if !item.isPickedUp {
                    HStack(spacing: 6) {
                        if !item.quantity.isEmpty {
                            ChipView(text: "Qty: \(item.quantity)",
                                     fill: AppColors.secondaryContainer, content: AppColors.onSecondaryContainer)
                        }
                        if let category = item.category {
                            ChipView(text: category,
                                     fill: AppColors.tertiaryContainer, content: AppColors.onTertiaryContainer)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(item.isPickedUp ? AppColors.surfaceContainer : AppColors.surfaceContainerLow,
                    in: RoundedRectangle(cornerRadius: AppMetrics.tileRadius, style: .continuous))
        .overlay {
            if !item.isPickedUp {
                RoundedRectangle(cornerRadius: AppMetrics.tileRadius, style: .continuous)
                    .strokeBorder(AppColors.outline.opacity(0.3), lineWidth: 0.5)
            }
        }
        .shadow(color: AppColors.shadow.opacity(item.isPickedUp ? 0 : 0.06), radius: 3, y: 1)
        .animation(.easeOut(duration: 0.22), value: item.isPickedUp)
    }
}

struct ChipView: View {
    let text: String
    let fill: Color
    let content: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(content)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(content.opacity(0.15), lineWidth: 0.5)
            }
    }
}

/// Bottom snackbar offering to undo a delete.
struct UndoSnackbar: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColors.surface)
                .lineLimit(1)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.primaryContainer)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(AppColors.textPrimary, in: RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous))
        .padding(.horizontal, AppMetrics.screenPadding)
        .accessibilityElement(children: .contain)
    }
}
