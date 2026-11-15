import Foundation
import Observation

/// The signed-in user as the profile sheet sees it (Android `AuthStateManager.userName` /
/// `userEmail` / `dataOwnerId()`).
@MainActor
protocol ProfileAccountSource: AnyObject {
    /// Whose lists are on the phone: the account, also after a lost session.
    var dataOwnerId: String? { get }
    /// Calls `handler` with the name and email now and on every change, like collecting
    /// Android's `combine(userName, userEmail)`.
    func observeProfile(_ handler: @escaping @MainActor @Sendable (String?, String?) -> Void) -> AuthStateSubscription
}

/// The account operations the sheet needs (a slice of `AuthRepository`).
protocol ProfileAuthenticating: Sendable {
    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError>
    func logout() async -> Result<Void, AppError>
    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError>
}

/// The sync work around signing out and deleting the account (`SyncEngine`, ACCT-06).
protocol ProfileSyncing: Sendable {
    /// Best effort: a push that can't run (offline, lost session) just leaves the queue.
    func push() async
    func hasUnsyncedChanges(accountId: String) async -> Bool
    /// Takes the account's lists off the phone, then runs `andThen` (the sign-out) inside the
    /// same critical section. Returns the eviction's failure if it failed, else `andThen`'s result.
    func evictAccountLists(andThen: @Sendable () async -> Result<Void, AppError>) async -> Result<Void, AppError>
}

protocol ProfileWelcomeResetting: Sendable {
    func reset()
}

extension SupabaseAuthRepository: ProfileAuthenticating {}
extension WelcomeRepository: ProfileWelcomeResetting {}

extension AuthStateManager: ProfileAccountSource {
    @MainActor
    func observeProfile(_ handler: @escaping @MainActor @Sendable (String?, String?) -> Void) -> AuthStateSubscription {
        let tracker = ProfileFieldsTracker(source: self, handler: handler)
        tracker.track()
        return AuthStateSubscription { Task { @MainActor in tracker.stop() } }
    }
}

/// Re-reads the name and email each time either changes. `AuthStateManager` stores a value
/// before it publishes the change, but the read still hops to the next main-actor turn so it
/// never runs inside the mutation.
@MainActor
private final class ProfileFieldsTracker {
    private let source: AuthStateManager
    private let handler: @MainActor @Sendable (String?, String?) -> Void
    private var isActive = true

    init(source: AuthStateManager, handler: @escaping @MainActor @Sendable (String?, String?) -> Void) {
        self.source = source
        self.handler = handler
    }

    func track() {
        guard isActive else { return }
        let (name, email) = withObservationTracking {
            (source.userName, source.userEmail)
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        handler(name, email)
    }

    func stop() {
        isActive = false
    }
}

/// `SyncEngine` behind `ProfileSyncing`, resolved at call time so building the profile opens
/// no Supabase client. nil only once the container is gone.
struct DeferredProfileSync: ProfileSyncing {
    let engine: @MainActor @Sendable () -> SyncEngine?

    func push() async {
        guard let engine = await engine() else { return }
        _ = try? await engine.push()
    }

    /// A count that can't be read warns rather than silently losing edits.
    func hasUnsyncedChanges(accountId: String) async -> Bool {
        guard let engine = await engine() else { return true }
        return (try? await engine.hasUnsyncedChanges(accountId: accountId)) ?? true
    }

    func evictAccountLists(andThen signOut: @Sendable () async -> Result<Void, AppError>) async -> Result<Void, AppError> {
        guard let engine = await engine() else { return .failure(.unknown()) }
        let signOutResult = SignOutResultBox()
        let evicted: Result<Void, AppError>
        do {
            evicted = try await engine.evictAccountLists {
                let result = await signOut()
                signOutResult.set(result)
            }
        } catch {
            evicted = .failure(.unknown())
        }
        if case .failure = evicted { return evicted }
        return signOutResult.value
    }
}

private final class SignOutResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Void, AppError> = .success(())

    var value: Result<Void, AppError> { lock.withLock { stored } }

    func set(_ result: Result<Void, AppError>) {
        lock.withLock { stored = result }
    }
}

/// The container's auth repository, resolved at call time (it is built on first use).
struct DeferredProfileAuth: ProfileAuthenticating {
    let resolve: @MainActor @Sendable () -> any ProfileAuthenticating

    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError> {
        try await resolve().updateUserName(name)
    }

    func logout() async -> Result<Void, AppError> {
        await resolve().logout()
    }

    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError> {
        try await resolve().deleteAccount()
    }
}

/// What `DeferredProfileAuth` falls back to once the container is gone: every call fails.
struct UnavailableProfileAuth: ProfileAuthenticating {
    func updateUserName(_ name: String) async throws(CancellationError) -> Result<AuthUser, AppError> { .failure(.unknown()) }
    func logout() async -> Result<Void, AppError> { .failure(.unknown()) }
    func deleteAccount() async throws(CancellationError) -> Result<Void, AppError> { .failure(.unknown()) }
}
