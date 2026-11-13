import SwiftUI

/// Brand colours ported from the Android Compose theme (ui/theme/Color.kt, Theme.kt).
/// Each asset has a light and a dark variant. `primary` is the app's global tint (AccentColor).
enum AppColors {
    static let primary = Color.accentColor
    static let onPrimary = Color("OnPrimary")
    static let primaryContainer = Color("PrimaryContainer")
    static let onPrimaryContainer = Color("OnPrimaryContainer")

    static let secondary = Color("Secondary")
    static let secondaryContainer = Color("SecondaryContainer")
    static let onSecondaryContainer = Color("OnSecondaryContainer")

    static let tertiary = Color("Tertiary")
    static let tertiaryContainer = Color("TertiaryContainer")
    static let onTertiaryContainer = Color("OnTertiaryContainer")

    static let background = Color("Background")
    static let surface = Color("Surface")
    static let surfaceContainerLowest = Color("SurfaceContainerLowest")
    /// Card fill. Lifts off `background` in both light and dark mode.
    static let surfaceContainerLow = Color("SurfaceContainerLow")
    static let surfaceContainer = Color("SurfaceContainer")
    static let surfaceContainerHigh = Color("SurfaceContainerHigh")
    static let surfaceContainerHighest = Color("SurfaceContainerHighest")

    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let outline = Color("Outline")
    /// Card and FAB drop shadow. Black in light mode, clear in dark mode, where Android's
    /// card elevation is tonal (the lighter container fill) rather than a shadow.
    /// Apply the elevation's strength with `.opacity(_:)`.
    static let shadow = Color("Shadow")

    /// Form and field errors. Android's Theme.kt sets no error colours, so these are the
    /// Material 3 baseline `error` / `onError` (Error40 / Error100 light, Error80 / Error20 dark).
    static let error = Color("Error")
    static let onError = Color("OnError")

    /// Swipe-to-delete background (Android SwipeableCard red 0xE53935). Android uses the same
    /// value in light and dark, so both appearances match.
    static let swipeDelete = Color("SwipeDelete")
    /// Swipe-to-complete background (Android SwipeableCard green 0x43A047), same in both modes.
    static let swipeComplete = Color("SwipeComplete")
    /// Icon on a swipe background (Android `Color.White`).
    static let onSwipe = Color("OnSwipe")

    /// The pebble mascot on the voice recording screen (Android PebbleListeningIndicator.kt,
    /// matching the app-icon mascot). Android uses the same values in light and dark.
    static let pebbleSlate = Color("PebbleSlate")
    static let pebbleCream = Color("PebbleCream")
    static let pebblePupil = Color("PebblePupil")
    static let pebbleBlush = Color("PebbleBlush")
    static let pebbleEye = Color("PebbleEye")

    /// Every named colour asset, so a test can prove none is missing.
    static let assetNames = [
        "AccentColor", "OnPrimary", "PrimaryContainer", "OnPrimaryContainer",
        "Secondary", "SecondaryContainer", "OnSecondaryContainer",
        "Tertiary", "TertiaryContainer", "OnTertiaryContainer",
        "Background", "Surface", "SurfaceContainerLowest", "SurfaceContainerLow",
        "SurfaceContainer", "SurfaceContainerHigh", "SurfaceContainerHighest",
        "TextPrimary", "TextSecondary", "Outline", "Shadow", "Error", "OnError",
    ] + (0..<ListAccent.count).flatMap { ["ListAccent\($0)Container", "ListAccent\($0)OnContainer"] }

    /// Assets that are deliberately the same in light and dark, because Android's are.
    static let fixedAssetNames = [
        "SwipeDelete", "SwipeComplete", "OnSwipe",
        "PebbleSlate", "PebbleCream", "PebblePupil", "PebbleBlush", "PebbleEye",
    ]
}

/// Muted per-list accent (icon tile behind the cart), picked from the list id exactly like
/// Android's `getAccentForList`, so a shared list has the same colour on both platforms.
struct ListAccent: Equatable {
    static let count = 8

    let index: Int
    var container: Color { Color("ListAccent\(index)Container") }
    var onContainer: Color { Color("ListAccent\(index)OnContainer") }

    init(index: Int) {
        precondition((0..<Self.count).contains(index))
        self.index = index
    }

    /// Android: `abs(listId.hashCode()) % palette.size`.
    init(listId: String) {
        self.init(index: Int(javaHashCode(listId).magnitude % UInt32(Self.count)))
    }
}

/// `java.lang.String.hashCode()`: s[0]*31^(n-1) + … + s[n-1] over UTF-16 units, wrapping Int32.
func javaHashCode(_ string: String) -> Int32 {
    string.utf16.reduce(Int32(0)) { hash, unit in hash &* 31 &+ Int32(unit) }
}
