import SwiftUI

/// Decides when the progress card celebrates (Android `ProgressCard`'s `hasInitialized` guard):
/// only on a change from not finished to finished, never for the first value it is shown,
/// so opening a finished list doesn't replay the celebration.
struct ProgressCardCelebration: Equatable {
    private var lastAllDone: Bool?

    /// Feed every value the card shows, starting with the first. Returns whether to celebrate now.
    mutating func update(allDone: Bool) -> Bool {
        defer { lastAllDone = allDone }
        return lastAllDone == false && allDone
    }
}

/// "3 of 7 picked up", percentage badge and progress bar (Android `ProgressCard`).
/// On the transition to finished the card pops from 0.85 back to 1 with a spring, the check
/// pops in with a bouncy spring, and the container pulses toward primary and back.
/// The Success haptic is the view model's (`ListDetailViewModel.completionCount`).
struct ProgressCardView: View {
    let total: Int
    let pickedUp: Int

    @State private var celebration = ProgressCardCelebration()
    @State private var cardScale: CGFloat = 1
    @State private var checkScale: CGFloat = 1
    @State private var pulse: Double = 0

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
                            .scaleEffect(checkScale)
                            .transition(.scale.combined(with: .opacity))
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
        .background {
            // The pulse blends the container toward primary and back (Android `lerp`).
            RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                .fill(allDone ? AppColors.primaryContainer : AppColors.surfaceContainerLow)
                .overlay {
                    RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                        .fill(AppColors.primary.opacity(pulse))
                }
        }
        .overlay {
            if !allDone {
                RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                    .strokeBorder(AppColors.outline.opacity(0.3), lineWidth: 0.5)
            }
        }
        .shadow(color: AppColors.shadow.opacity(0.08), radius: 4, y: 2)
        .scaleEffect(cardScale)
        .animation(.easeOut(duration: 0.2), value: allDone)
        .onChange(of: allDone, initial: true) { _, done in
            if celebration.update(allDone: done) {
                celebrate()
            } else if !done {
                // Unticking or re-opening: reset without animating.
                checkScale = 0
                pulse = 0
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func celebrate() {
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            cardScale = 0.85
            checkScale = 0
            pulse = 0
        }
        // Spring.DampingRatioLowBouncy (0.75) and DampingRatioHighBouncy (0.2) at StiffnessMediumLow.
        withAnimation(.interpolatingSpring(stiffness: 1500, damping: 2 * 0.75 * sqrt(1500))) { cardScale = 1 }
        withAnimation(.interpolatingSpring(stiffness: 400, damping: 2 * 0.2 * sqrt(400))) { checkScale = 1 }
        withAnimation(.easeOut(duration: 0.18)) {
            pulse = 1
        } completion: {
            withAnimation(.easeInOut(duration: 0.32)) { pulse = 0 }
        }
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

/// What an item card can do: the tick circle and a swipe right toggle picked up, a tap edits,
/// a swipe left deletes.
struct ItemCardActions {
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// The actions of one row of the list detail screen: toggling goes to the view model,
    /// edit and delete are the screen's.
    @MainActor
    static func forItem(_ item: ShoppingItem, in model: ListDetailViewModel,
                        onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) -> ItemCardActions {
        ItemCardActions(onToggle: { Task { await model.toggle(item.id) } }, onEdit: onEdit, onDelete: onDelete)
    }

    /// The swipeable card the screen shows for `item`: swipe right toggles, swipe left deletes.
    /// The screen and the tests both build the row through here.
    @MainActor
    func card<Content: View>(for item: ShoppingItem, haptics: any HapticPlaying = SystemHapticPlayer(),
                             @ViewBuilder content: () -> Content) -> SwipeableCard<Content> {
        // SwipeableCard plays the swipe's own haptic; the tick circle plays its own.
        SwipeableCard(
            onSwipeLeft: onDelete,
            onSwipeRight: onToggle,
            rightIcon: item.isPickedUp ? "arrow.uturn.backward" : "checkmark",
            leftActionName: "Delete",
            rightActionName: item.isPickedUp ? "Mark as not picked up" : "Mark as picked up",
            haptics: haptics,
            content: content)
    }
}

/// One item: tick circle, name, italic note, quantity and category chips (Android `ShoppingItemCard`).
/// Tapping the card (not the circle) opens the editor.
struct ItemCardView: View {
    let item: ShoppingItem
    let onToggle: () -> Void
    var onEdit: () -> Void = {}

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
                        if let category = item.categoryName {
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
        .contentShape(RoundedRectangle(cornerRadius: AppMetrics.tileRadius, style: .continuous))
        .onTapGesture(perform: onEdit)
        .accessibilityAction(named: "Edit", onEdit)
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
        Snackbar(message: message, actionTitle: "Undo", action: onUndo, lineLimit: 1)
    }
}

/// Empty-list state shown instead of the item list (Android `FirstItemPrompt`).
struct FirstItemPromptView: View {
    let onAddItem: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BrandMark()
            Text("List created!")
                .font(.title2.bold())
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, 24)
            Text("Add your first item to get started")
                .font(.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Button(action: onAddItem) {
                Label("Add first item", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 32)
            .accessibilityIdentifier("add-first-item-button")
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
