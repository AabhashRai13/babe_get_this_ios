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
    private static var threshold: CGFloat { 100 }

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
                        let proposed = value.translation.width
                        let dir: SwipeDirection = proposed < 0 ? .towardLeading : .towardTrailing
                        if controller.isAllowed(dir) { offset = proposed }
                    }
                    .onEnded { _ in
                        if let direction, abs(offset) >= Self.threshold {
                            controller.settle(direction)
                        }
                        withAnimation(.snappy) { offset = 0 }
                    }
            )
    }
}
