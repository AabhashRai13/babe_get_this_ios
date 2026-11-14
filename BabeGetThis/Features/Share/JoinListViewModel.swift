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

/// The join dialog's code field (Android `JoinListDialog`'s `code` state). A fresh one per
/// dialog, so the field starts empty each time it opens. The join itself, its progress and its
/// error belong to `ListsViewModel`.
@MainActor
@Observable
final class JoinListViewModel {
    static let codeLength = 6

    private(set) var code = ""

    /// Trimmed, uppercased and capped at six. The join RPC uppercases server-side too; doing it
    /// here just makes the field match what was texted.
    func updateCode(_ raw: String) {
        code = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(Self.codeLength))
    }

    /// "Join" needs exactly six characters, and no join already running.
    func isJoinEnabled(isJoining: Bool) -> Bool {
        code.count == Self.codeLength && !isJoining
    }
}
