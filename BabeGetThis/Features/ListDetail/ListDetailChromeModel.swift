import Foundation
import Observation

/// A top-bar action of the list detail screen, in display order (Android `ShoppingItemsScreen` top bar).
/// Android's lock toggle is out of v1.
enum ListDetailTopBarAction: String, CaseIterable, Identifiable, Equatable {
    case shareLive
    case shareAsText

    var id: String { rawValue }

    /// Android `share_live_action` / `share_as_text`; also the accessibility label.
    var title: String {
        switch self {
        case .shareLive: "Share live"
        case .shareAsText: "Share as text"
        }
    }

    var systemImage: String {
        switch self {
        case .shareLive: "person.2"
        case .shareAsText: "square.and.arrow.up"
        }
    }
}

/// Chrome state of the list detail screen: the voice FAB's sign-in gate and the top-bar
/// actions (Android `ShoppingItemsScreen` FABs and top bar, DET-10, DET-11).
@MainActor
@Observable
final class ListDetailChromeModel {
    /// Display order: "Share live", then "Share as text".
    static let topBarActions: [ListDetailTopBarAction] = [.shareLive, .shareAsText]

    let listName: String
    @ObservationIgnored private let authState: () -> AuthState
    @ObservationIgnored private let haptics: any HapticPlaying

    /// The sign-in prompt for a gated feature, nil when none is showing.
    private(set) var authPrompt: AuthPromptContent?
    /// Where the prompt sends a guest.
    var authRoute: AuthRoute?
    /// The voice capture sheet is up (signed-in accounts only).
    var isVoicePresented = false
    /// The Share live sheet is up (signed-in accounts only).
    var isShareLivePresented = false
    /// Text handed to the system share sheet; nil when it isn't showing.
    var sharedText: String?
    /// The list's items as they are now. Read when "Share as text" is tapped, never captured
    /// earlier, so the share always matches the screen.
    @ObservationIgnored private let items: @MainActor () -> [ShoppingItem]

    typealias AuthRoute = ListsViewModel.AuthRoute

    init(listName: String,
         authState: @escaping () -> AuthState,
         haptics: any HapticPlaying = SystemHapticPlayer(),
         items: @escaping @MainActor () -> [ShoppingItem] = { [] }) {
        self.listName = listName
        self.authState = authState
        self.haptics = haptics
        self.items = items
    }

    private var isAuthenticated: Bool {
        if case .authenticated = authState() { true } else { false }
    }

    /// Mic FAB: medium haptic, then the voice sheet when signed in, else the sign-in prompt.
    func voiceFabTapped() {
        haptics.play(.medium)
        if isAuthenticated {
            isVoicePresented = true
        } else {
            authPrompt = .voice
        }
    }

    /// Both top-bar actions play a Light haptic first (Android `haptic(Haptic.Light)`).
    func perform(_ action: ListDetailTopBarAction) {
        haptics.play(.light)
        switch action {
        case .shareLive: shareLiveTapped()
        case .shareAsText: shareAsTextTapped()
        }
    }

    private func shareLiveTapped() {
        if isAuthenticated {
            isShareLivePresented = true
        } else {
            authPrompt = .share
        }
    }

    /// The session was lost while the Share live sheet opened: close it and show the prompt.
    func shareLiveNeedsSignIn() {
        isShareLivePresented = false
        authPrompt = .share
    }

    private func shareAsTextTapped() {
        sharedText = ShoppingListShareText.format(listName: listName, items: items())
    }

    /// The system share sheet finished (an activity ran, or it was closed). UIKit dismisses it
    /// without SwiftUI noticing, so this clears the text and the next share presents again.
    func shareSheetFinished() { sharedText = nil }

    func dismissAuthPrompt() { authPrompt = nil }

    func promptSignIn() {
        authPrompt = nil
        authRoute = .login
    }

    func promptCreateAccount() {
        authPrompt = nil
        authRoute = .register
    }
}
