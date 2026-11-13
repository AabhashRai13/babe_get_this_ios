import Foundation
import Observation

/// What leaving the list detail screen needs from `ShoppingListRepository`. A seam so tests
/// can hold the delete back; the app passes the repository itself.
protocol ListLeaveCleaning: Sendable {
    func shareCode(listId: String) -> AsyncThrowingStream<String?, any Error>
    func deleteListIfEmpty(listId: String) async throws -> Result<Bool, AppError>
}

extension ShoppingListRepository: ListLeaveCleaning {}

/// Leaving an empty list deletes it (Android `ShoppingItemsViewModel.onCleared`), which came as
/// a surprise, so the screen asks first (DET-12). Owns the share state the question depends on,
/// the in-flight undo the teardown must wait for, and the teardown itself.
@MainActor
@Observable
final class ListLeaveGuard {
    /// Copy from Android `strings.xml` (`leave_empty_list_*`).
    static let title = "Delete this empty list?"
    static let message = "This list has no items, so it will be deleted when you leave."
    static let confirmTitle = "Delete list"
    static let stayTitle = "Keep editing"

    let listId: String
    private let cleaner: any ListLeaveCleaning

    /// nil until the database has answered, so nothing is claimed about a list not yet read.
    private var shareCodeState: ShareCodeState = .unknown
    /// Whether the "Delete this empty list?" dialog is up.
    var isConfirming = false
    /// A just-tapped undo may still be restoring its item when the screen goes.
    @ObservationIgnored private var restoreTask: Task<Void, Never>?

    private enum ShareCodeState: Equatable {
        case unknown
        case known(String?)
    }

    init(listId: String, cleaner: any ListLeaveCleaning) {
        self.listId = listId
        self.cleaner = cleaner
    }

    /// True when leaving now would delete the list. Shared lists are never auto-removed, so
    /// they never ask. False until both the items and the share state have loaded: a back
    /// press before the first read must never ask wrongly.
    func leavingDeletesList(_ model: ListDetailViewModel) -> Bool {
        guard model.hasLoaded, case .known(let code) = shareCodeState else { return false }
        return model.isEmpty && code == nil
    }

    /// The back button: asks when leaving would delete the list, otherwise leaves.
    /// Returns whether the screen should leave now.
    func backTapped(_ model: ListDetailViewModel) -> Bool {
        if leavingDeletesList(model) {
            isConfirming = true
            return false
        }
        return true
    }

    /// "Keep editing".
    func stay() {
        isConfirming = false
    }

    /// "Delete list": closes the dialog; leaving does the delete.
    func confirmLeave() {
        isConfirming = false
    }

    /// Follows the list's share state until the calling task is cancelled.
    func observeShareCode() async {
        do {
            for try await code in cleaner.shareCode(listId: listId) {
                shareCodeState = .known(code)
            }
        } catch {
            // Unknown share state: never ask, and the repository re-checks on teardown anyway.
            shareCodeState = .unknown
        }
    }

    /// Runs an undo so the teardown can wait for it. Not tied to the screen: an undo
    /// tapped just before leaving still runs.
    func trackUndo(_ undo: @escaping @MainActor () async -> Void) {
        let previous = restoreTask
        restoreTask = Task {
            await previous?.value
            await undo()
        }
    }

    /// The screen is gone: any list left with zero items is cleaned up, whether just created
    /// and abandoned or emptied out. Waits for an in-flight undo first so the emptiness
    /// check sees the restored row and keeps the list. Not tied to the screen.
    @discardableResult
    func tearDown() -> Task<Void, Never> {
        let restore = restoreTask
        let cleaner = cleaner
        let listId = listId
        return Task {
            await restore?.value
            // The repository re-checks the real item count; a failure just keeps the list.
            _ = try? await cleaner.deleteListIfEmpty(listId: listId)
        }
    }
}
