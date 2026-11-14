import Foundation
import Observation
import UIKit

/// Giving a list its share code (Android `ShareRepository.share`). Succeeds with the code.
protocol ListSharing: Sendable {
    func share(listId: String) async throws -> Result<String, AppError>
}

extension ShareRepository: ListSharing {}

/// Android `share_live_*` and `done` strings.
enum ShareLiveCopy {
    static let title = "Share list live"
    static let hint = "Anyone with this code can see and edit this list. Text it to them, and they enter it under \"Join a shared list\"."
    static let copy = "Copy"
    static let done = "Done"
}

/// The share-live flow of the list detail screen (Android `ShoppingItemsViewModel.onShareLiveClick`
/// and its `shareCodeDialog` / `showShareAuthPrompt` state). The code is static per list, so
/// sharing again shows the same one. Only the code is shown: never who changed what (SHARE-06).
@MainActor
@Observable
final class ShareLiveViewModel {
    let listId: String
    /// The code the dialog is showing, nil when it isn't.
    private(set) var shareCode: String?
    /// Live sharing needs an account; this asks a guest to sign in.
    private(set) var showsAuthPrompt = false
    /// A failed share's message, for a snackbar.
    var errorMessage: String?
    /// A share is on its way to the server.
    private(set) var isSharing = false

    @ObservationIgnored private let authState: () -> AuthState
    @ObservationIgnored private let sharer: any ListSharing
    @ObservationIgnored private let copyToClipboard: @MainActor (String) -> Void

    init(listId: String,
         authState: @escaping () -> AuthState,
         sharer: any ListSharing,
         copyToClipboard: @escaping @MainActor (String) -> Void = { UIPasteboard.general.string = $0 }) {
        self.listId = listId
        self.authState = authState
        self.sharer = sharer
        self.copyToClipboard = copyToClipboard
    }

    /// A lost session can't reach the server either, so only a live one counts.
    private var isAuthenticated: Bool {
        if case .authenticated = authState() { true } else { false }
    }

    /// Generates (or re-shows) the list's code.
    func shareLive() async {
        guard isAuthenticated else {
            showsAuthPrompt = true
            return
        }
        isSharing = true
        defer { isSharing = false }
        let result: Result<String, AppError>
        do {
            result = try await sharer.share(listId: listId)
        } catch {
            return // Cancelled.
        }
        switch result {
        case .success(let code): shareCode = code
        case .failure(let error): errorMessage = error.message
        }
    }

    /// Copying is the sharing act: the user pastes the code into whatever app they already
    /// talk in (no share sheet, Android product decision 001).
    func copyCode() {
        guard let shareCode else { return }
        copyToClipboard(shareCode)
    }

    func dismissShareCode() { shareCode = nil }

    func dismissAuthPrompt() { showsAuthPrompt = false }
}
