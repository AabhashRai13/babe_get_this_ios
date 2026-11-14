import Foundation
import Observation

/// The profile sheet's state (Android `ProfileViewModel`): the name being edited, sign-out with
/// the unsynced-changes warning (PROF-02) and account deletion (PROF-03).
///
/// Owned by the container, not the sheet: signing out and deleting flip the auth state, which
/// closes the sheet, and the work that follows (taking the lists off the phone, resetting
/// Welcome, the deletion message) must still finish and show.
@MainActor
@Observable
final class ProfileViewModel {
    nonisolated static let nameEmptyMessage = "Name cannot be empty"
    nonisolated static let nameUpdatedMessage = "Name updated"
    nonisolated static let accountDeletedMessage = "Your account has been deleted"

    /// One message for the snackbar; a new id per message so a repeat shows again.
    struct Toast: Equatable, Identifiable {
        let id = UUID()
        let message: String
    }

    private(set) var userName = ""
    private(set) var userEmail = ""
    private(set) var editedName = ""
    private(set) var isSaving = false
    private(set) var isLoggingOut = false
    private(set) var isDeletingAccount = false
    /// Some changes never reached the server; signing out now would lose them.
    private(set) var showUnsyncedSignOutWarning = false
    private(set) var toast: Toast?

    /// True when the user has typed a different name than what's saved.
    var hasNameChanged: Bool {
        !editedName.allSatisfy(\.isWhitespace) && editedName != userName
    }

    /// The latest save, sign-out or deletion, so callers (and tests) can wait for it.
    @ObservationIgnored private(set) var inFlight: Task<Void, Never>?

    @ObservationIgnored private let account: any ProfileAccountSource
    @ObservationIgnored private let auth: any ProfileAuthenticating
    @ObservationIgnored private let sync: any ProfileSyncing
    @ObservationIgnored private let welcome: any ProfileWelcomeResetting
    @ObservationIgnored private var subscription: AuthStateSubscription?

    init(account: any ProfileAccountSource, auth: any ProfileAuthenticating,
         sync: any ProfileSyncing, welcome: any ProfileWelcomeResetting) {
        self.account = account
        self.auth = auth
        self.sync = sync
        self.welcome = welcome
        // Observed, not snapshotted: this instance outlives a logout→login, and a one-time read
        // would keep showing the previous account's name and email.
        subscription = account.observeProfile { [weak self] name, email in
            guard let self else { return }
            userName = name ?? ""
            userEmail = email ?? ""
            editedName = name ?? ""
        }
    }

    /// Called as the user types in the name field.
    func onNameChanged(_ newName: String) {
        editedName = newName
    }

    /// Saves the edited name to the backend (and locally).
    func saveName() {
        let newName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            show(Self.nameEmptyMessage)
            return
        }
        isSaving = true
        inFlight = Task { [auth] in
            let result: Result<AuthUser, AppError>
            do {
                result = try await auth.updateUserName(newName)
            } catch {
                isSaving = false
                return
            }
            switch result {
            case .success(let user):
                userName = user.name
                editedName = user.name
                isSaving = false
                show(Self.nameUpdatedMessage)
            case .failure(let error):
                isSaving = false
                show(error.message)
            }
        }
    }

    /// Permanent server-side deletion. The account's lists leave the phone with it, but only
    /// once the account is gone: a deletion that fails (offline, server error) must leave every
    /// list and unsynced edit in place.
    func deleteAccount() {
        isDeletingAccount = true
        inFlight = Task { [auth, sync, welcome] in
            // Push while the session still exists.
            await sync.push()
            let result: Result<Void, AppError>
            do {
                result = try await auth.deleteAccount()
            } catch {
                isDeletingAccount = false
                return
            }
            switch result {
            case .success:
                _ = await sync.evictAccountLists(andThen: { .success(()) })
                isDeletingAccount = false
                welcome.reset()
                show(Self.accountDeletedMessage)
            case .failure(let error):
                isDeletingAccount = false
                show(error.message)
            }
        }
    }

    /// Signing out takes every account list off the phone. Push first; if anything still
    /// hasn't reached the server (offline), ask before throwing it away.
    func logout() {
        isLoggingOut = true
        inFlight = Task { [account, sync] in
            await sync.push()
            // The owner, not the live session: after a lost session the push above was a
            // no-op, and this is exactly when the queue is full.
            if let owner = account.dataOwnerId, await sync.hasUnsyncedChanges(accountId: owner) {
                isLoggingOut = false
                showUnsyncedSignOutWarning = true
            } else {
                await completeSignOut()
            }
        }
    }

    func confirmSignOutAnyway() {
        showUnsyncedSignOutWarning = false
        isLoggingOut = true
        inFlight = Task { await completeSignOut() }
    }

    func dismissUnsyncedSignOutWarning() {
        showUnsyncedSignOutWarning = false
    }

    /// Clears the snackbar, unless a newer message replaced it meanwhile.
    func dismissToast(id: Toast.ID) {
        if toast?.id == id { toast = nil }
    }

    /// The explicit sign-out path only; a lost session never evicts. The sign-out runs inside
    /// the eviction's critical section, so the final push still has a session and no sync kick
    /// can land the lists again in between.
    private func completeSignOut() async {
        let result = await sync.evictAccountLists(andThen: { [auth] in await auth.logout() })
        isLoggingOut = false
        switch result {
        case .success:
            // The next launch starts on Welcome too; the start screen reacts to the sign-out.
            welcome.reset()
        case .failure(let error):
            show(error.message)
        }
    }

    private func show(_ message: String) {
        toast = Toast(message: message)
    }
}
