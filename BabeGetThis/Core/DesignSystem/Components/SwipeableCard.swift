import SwiftUI

enum SwipeDirection: Equatable, Sendable {
    /// Content dragged left: destructive action (delete).
    case towardLeading
    /// Content dragged right: optional toggle action.
    case towardTrailing
}

/// Decision logic of the swipeable card, kept free of UI so it can be tested.
/// The action fires in `settle`, once per settled swipe, never in `isAllowed`.
@MainActor
final class SwipeableCardController {
    private let onSwipeLeft: () -> Void
    private let onSwipeRight: (() -> Void)?
    private let haptics: HapticPlaying

    init(onSwipeLeft: @escaping () -> Void, onSwipeRight: (() -> Void)? = nil, haptics: HapticPlaying) {
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
        self.haptics = haptics
    }

    /// Whether a direction may be dismissed. Side-effect free; may be consulted any number of times.
    func isAllowed(_ direction: SwipeDirection) -> Bool {
        direction == .towardLeading || onSwipeRight != nil
    }

    /// Android material3 1.3 `SwipeToDismissBox`: dismisses past 56dp, or on a fling faster
    /// than 125dp/s.
    static let positionalThreshold: CGFloat = 56
    static let velocityThreshold: CGFloat = 125

    /// Where the card sits for a drag translation. A disallowed direction stays at rest, so
    /// dragging back across the start never keeps the other side's offset.
    func offset(forTranslation translation: CGFloat) -> CGFloat {
        guard let direction = Self.direction(of: translation) else { return 0 }
        return isAllowed(direction) ? translation : 0
    }

    /// The direction a released drag settles in, decided from the final translation and
    /// velocity (never a stored offset). A fling moves to the next anchor in its direction:
    /// away from rest dismisses that side, back toward rest snaps back.
    func target(translation: CGFloat, velocity: CGFloat) -> SwipeDirection? {
        let side = Self.direction(of: translation)
        let candidate: SwipeDirection?
        if abs(velocity) >= Self.velocityThreshold, let side {
            candidate = Self.direction(of: velocity) == side ? side : nil
        } else if abs(translation) >= Self.positionalThreshold {
            candidate = side
        } else {
            candidate = nil
        }
        guard let candidate, isAllowed(candidate) else { return nil }
        return candidate
    }

    /// A released drag: settles (and fires once) if it reached a dismiss target.
    func end(translation: CGFloat, velocity: CGFloat) {
        if let direction = target(translation: translation, velocity: velocity) {
            settle(direction)
        }
    }

    private static func direction(of value: CGFloat) -> SwipeDirection? {
        value < 0 ? .towardLeading : value > 0 ? .towardTrailing : nil
    }

    /// Called when a swipe has settled past its threshold. Fires the action and haptic once.
    func settle(_ direction: SwipeDirection) {
        switch direction {
        case .towardLeading:
            haptics.play(.medium)
            onSwipeLeft()
        case .towardTrailing:
            guard let onSwipeRight else { return }
            haptics.play(.light)
            onSwipeRight()
        }
    }
}

/// Swipe wrapper for cards: red trash on swipe left, optional green check on swipe right.
/// The card snaps back after the action fires.
struct SwipeableCard<Content: View>: View {
    private let controller: SwipeableCardController
    private let leftIcon: String
    private let rightIcon: String
    private let content: Content
    @State private var offset: CGFloat = 0

    init(
        onSwipeLeft: @escaping () -> Void,
        onSwipeRight: (() -> Void)? = nil,
        leftIcon: String = "trash",
        rightIcon: String = "checkmark",
        haptics: HapticPlaying = SystemHapticPlayer(),
        @ViewBuilder content: () -> Content
    ) {
        controller = SwipeableCardController(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight, haptics: haptics)
        self.leftIcon = leftIcon
        self.rightIcon = rightIcon
        self.content = content()
    }

    private var direction: SwipeDirection? {
        offset < 0 ? .towardLeading : offset > 0 ? .towardTrailing : nil
    }

    var body: some View {
        content
            .offset(x: offset)
            .background(alignment: offset < 0 ? .trailing : .leading) {
                if let direction {
                    RoundedRectangle(cornerRadius: AppMetrics.tileRadius)
                        .fill((direction == .towardLeading ? AppColors.swipeDelete : AppColors.swipeComplete).opacity(0.9))
                        .overlay(alignment: direction == .towardLeading ? .trailing : .leading) {
                            Image(systemName: direction == .towardLeading ? leftIcon : rightIcon)
                                .foregroundStyle(AppColors.onSwipe)
                                .padding(.horizontal, 20)
                        }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        offset = controller.offset(forTranslation: value.translation.width)
                    }
                    .onEnded { value in
                        controller.end(translation: value.translation.width, velocity: value.velocity.width)
                        withAnimation(.snappy) { offset = 0 }
                    }
            )
    }
}
