import CoreGraphics

/// Shared spacing and corner radii, matching the Android screens.
enum AppMetrics {
    static let screenPadding: CGFloat = 16
    static let welcomePadding: CGFloat = 24

    static let cardRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 16
    static let tileRadius: CGFloat = 14

    static let buttonHeight: CGFloat = 56
    static let listTileSize: CGFloat = 48

    /// Round FAB (the list detail voice FAB, Android `SmallFloatingActionButton`). Android's is
    /// 40dp; 48 keeps the iOS 44pt minimum touch target.
    static let smallFABSize: CGFloat = 48
    /// Gap between stacked FABs (Android `Arrangement.spacedBy(12.dp)`).
    static let fabSpacing: CGFloat = 12
    /// FAB shadow, shared by `TonalFABStyle` and the round FAB.
    static let fabShadowRadius: CGFloat = 8
    static let fabShadowY: CGFloat = 3
}
