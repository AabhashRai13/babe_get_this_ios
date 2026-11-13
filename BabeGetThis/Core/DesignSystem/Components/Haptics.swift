import SwiftUI
import UIKit

/// Named haptic intents, ported from Android `Haptic`. Call sites say what the buzz means.
enum Haptic: CaseIterable, Sendable {
    case light, medium, heavy, success
}

/// The physical effect a `Haptic` resolves to. Android has only two: TextHandleMove and LongPress.
enum HapticEffect: Equatable, Sendable {
    case lightImpact
    case mediumImpact
}

extension Haptic {
    /// Same collapse as Android: Light is its own effect; Medium, Heavy and Success share one.
    var effect: HapticEffect {
        switch self {
        case .light: .lightImpact
        case .medium, .heavy, .success: .mediumImpact
        }
    }
}

/// Seam so tests can record which haptic fired.
@MainActor
protocol HapticPlaying {
    func play(_ haptic: Haptic)
}

@MainActor
struct SystemHapticPlayer: HapticPlaying {
    func play(_ haptic: Haptic) {
        switch haptic.effect {
        case .lightImpact: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .mediumImpact: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
