import Foundation
@testable import BabeGetThis

/// Every call the profile fakes saw, in order, across all of them (MockK `coVerifyOrder`).
final class ProfileCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []

    var calls: [String] { lock.withLock { _calls } }

    func record(_ call: String) {
        lock.withLock { _calls.append(call) }
    }

    func count(_ call: String) -> Int {
        calls.filter { $0 == call }.count
    }

    /// True when `expected` appears in this order (other calls may sit in between).
    func contains(inOrder expected: [String]) -> Bool {
        var remaining = expected[...]
        for call in calls where call == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}

/// The signed-in user's name and email as a hand-driven stream (Android `MutableStateFlow`).
@MainActor
final class FakeProfileAccount: ProfileAccountSource {
    var userName: String? { didSet { emit() } }
    var userEmail: String? { didSet { emit() } }
    var owner: String?
    private var handlers: [UUID: @MainActor @Sendable (String?, String?) -> Void] = [:]

    init(userName: String? = nil, userEmail: String? = nil, owner: String? = "u1") {
        self.userName = userName
        self.userEmail = userEmail
        self.owner = owner
    }

    var dataOwnerId: String? { owner }

    func observeProfile(_ handler: @escaping @MainActor @Sendable (String?, String?) -> Void) -> AuthStateSubscription {
        handlers[UUID()] = handler
        handler(userName, userEmail)
        return AuthStateSubscription {}
    }

    private func emit() {
        for handler in handlers.values { handler(userName, userEmail) }
    }
}

final class FakeProfileAuth: ProfileAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private let log: ProfileCallLog
    private var _updateNameCalls: [String] = []

    var updateNameResult: Result<AuthUser, AppError> = .success(AuthUser(id: "u1", email: "a@b.c", name: "Aabhash"))
    var logoutResult: Result<Void, AppError> = .success(())
    var deleteResult: Result<Void, AppError> = .success(())

    init(log: ProfileCallLog) {
        self.log = log
    }

    var updateNameCalls: [String] { lock.withLock { _updateNameCalls } }

    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError> {
        lock.withLock { _updateNameCalls.append(name) }
        log.record("updateUserName")
        return updateNameResult
    }

    func logout() async -> Result<Void, AppError> {
        log.record("logout")
        return logoutResult
    }

    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError> {
        log.record("deleteAccount")
        return deleteResult
    }
}

final class FakeProfileSync: ProfileSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private let log: ProfileCallLog
    private var _unsyncedQueries: [String] = []

    /// Like the relaxed MockK default: nothing unsynced unless a test says otherwise.
    var unsyncedAccounts: Set<String> = []
    /// nil: the real eviction, which runs the sign-out it is handed.
    var evictionFailure: AppError?

    init(log: ProfileCallLog) {
        self.log = log
    }

    var unsyncedQueries: [String] { lock.withLock { _unsyncedQueries } }

    func push() async {
        log.record("push")
    }

    func hasUnsyncedChanges(accountId: String) async -> Bool {
        lock.withLock { _unsyncedQueries.append(accountId) }
        log.record("hasUnsyncedChanges")
        return unsyncedAccounts.contains(accountId)
    }

    func evictAccountLists(andThen signOut: @Sendable () async -> Result<Void, AppError>) async -> Result<Void, AppError> {
        log.record("evictAccountLists")
        if let evictionFailure { return .failure(evictionFailure) }
        return await signOut()
    }
}

final class FakeProfileWelcome: ProfileWelcomeResetting, @unchecked Sendable {
    private let log: ProfileCallLog

    init(log: ProfileCallLog) {
        self.log = log
    }

    func reset() {
        log.record("welcome.reset")
    }
}
