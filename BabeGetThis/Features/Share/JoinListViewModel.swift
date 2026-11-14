import Foundation
import Observation

/// Android `join_list_*` strings.
enum JoinListCopy {
    static let title = "Join a shared list"
    static let fieldLabel = "6-character code"
    static let placeholder = "ABC234"
    static let join = "Join"
    static let cancel = "Cancel"
    /// The lists screen's top-bar button (Android `join_list_action`).
    static let action = "Join a shared list"
}

/// The join dialog's code field (Android `JoinListDialog`'s `code` state). `ListsViewModel` owns
/// it and clears it each time the dialog opens, so the field starts empty. The join itself, its
/// progress and its error belong to `ListsViewModel`.
@MainActor
@Observable
final class JoinListViewModel {
    nonisolated static let codeLength = 6

    private(set) var code = ""

    /// Trimmed, uppercased and capped at six (SHARE-04). The join RPC uppercases server-side
    /// too; doing it here just makes the field match what was texted. Codes never contain
    /// whitespace, so a space anywhere is dropped, not only at the ends (Android's `trim()`
    /// does the same for a space typed at the end, which is the only place typing puts one).
    nonisolated static func normalise(_ raw: String) -> String {
        String(raw.filter { !$0.isWhitespace }.uppercased().prefix(codeLength))
    }

    func updateCode(_ raw: String) {
        code = Self.normalise(raw)
    }

    /// The dialog is opening again: start from an empty field.
    func reset() { code = "" }

    /// "Join" needs exactly six characters, and no join already running.
    func isJoinEnabled(isJoining: Bool) -> Bool {
        code.count == Self.codeLength && !isJoining
    }
}
