import SwiftUI

/// Tap handling of the top bar: nav and action taps play a Light haptic, then call through.
@MainActor
struct TopAppBarActions {
    var onNavigationTap: (() -> Void)?
    var onActionTap: (() -> Void)?
    let haptics: HapticPlaying

    func navigationTapped() {
        guard let onNavigationTap else { return }
        haptics.play(.light)
        onNavigationTap()
    }

    func actionTapped() {
        guard let onActionTap else { return }
        haptics.play(.light)
        onActionTap()
    }
}

/// Top bar port of Android `BgtTopAppBar`. Large (bold title, home) or small (semibold, detail and settings).
/// A custom `actionSlot` replaces the default action icon button.
struct BgtTopAppBar<ActionSlot: View>: View {
    let title: String
    var navigationIcon: String?
    var showActionIcon = false
    var actionIcon = "square.and.arrow.up"
    var useLargeTopBar = false
    private let actions: TopAppBarActions
    private let actionSlot: ActionSlot?

    init(
        title: String,
        navigationIcon: String? = nil,
        onNavigationTap: (() -> Void)? = nil,
        showActionIcon: Bool = false,
        actionIcon: String = "square.and.arrow.up",
        onActionTap: (() -> Void)? = nil,
        useLargeTopBar: Bool = false,
        haptics: HapticPlaying = SystemHapticPlayer(),
        actionSlot: (() -> ActionSlot)? = nil
    ) {
        self.title = title
        self.navigationIcon = navigationIcon
        self.showActionIcon = showActionIcon
        self.actionIcon = actionIcon
        self.useLargeTopBar = useLargeTopBar
        actions = TopAppBarActions(onNavigationTap: onNavigationTap, onActionTap: onActionTap, haptics: haptics)
        self.actionSlot = actionSlot?()
    }

    var body: some View {
        HStack {
            if let navigationIcon, actions.onNavigationTap != nil {
                Button(action: actions.navigationTapped) { Image(systemName: navigationIcon) }
                    .foregroundStyle(AppColors.textPrimary)
            }
            Text(title)
                .font(useLargeTopBar ? .largeTitle.bold() : .title2.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionSlot {
                actionSlot
            } else if showActionIcon, actions.onActionTap != nil {
                Button(action: actions.actionTapped) { Image(systemName: actionIcon) }
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.vertical, useLargeTopBar ? 16 : 8)
        .background(AppColors.surface)
    }
}

extension BgtTopAppBar where ActionSlot == EmptyView {
    init(
        title: String,
        navigationIcon: String? = nil,
        onNavigationTap: (() -> Void)? = nil,
        showActionIcon: Bool = false,
        actionIcon: String = "square.and.arrow.up",
        onActionTap: (() -> Void)? = nil,
        useLargeTopBar: Bool = false,
        haptics: HapticPlaying = SystemHapticPlayer()
    ) {
        self.init(title: title, navigationIcon: navigationIcon, onNavigationTap: onNavigationTap,
                  showActionIcon: showActionIcon, actionIcon: actionIcon, onActionTap: onActionTap,
                  useLargeTopBar: useLargeTopBar, haptics: haptics, actionSlot: nil)
    }
}
