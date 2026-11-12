import Foundation
import Observation
import os
import UIKit

/// Single source of truth for "is the user logged in?" (Android `AuthStateManager`).
///
/// On launch `initialize()` restores the state from the `TokenStore`; navigation
/// observes `authState` to choose Welcome or the main app. A lost session (Supabase
/// gives up, or a 401) calls `expireSession()`, not `logout()`: the account's lists
/// stay on screen until the user signs in again (Android decision 008).
///
/// Every transition runs under one lock: Supabase reports a lost session on a
/// background thread while sign-in and sign-out run on the main actor, and a
/// read-then-write interleaved with another transition would leave a stale state
/// behind (e.g. a signed-out user stuck as "session expired").
@Observable
final class AuthStateManager: @unchecked Sendable {
    @ObservationIgnored private let tokenStore: TokenStore
    @ObservationIgnored private let lock = NSRecursiveLock()
    @ObservationIgnored private var storedAuthState: AuthState = .loading
    @ObservationIgnored private var storedUserName: String?
    @ObservationIgnored private var storedUserEmail: String?
    @ObservationIgnored private var observers: [UUID: @Sendable (AuthState) -> Void] = [:]
    @ObservationIgnored private let notificationCenter: NotificationCenter
    /// Set while `initialize()` waits for the Keychain to become readable.
    @ObservationIgnored private var protectedDataObserver: (any NSObjectProtocol)?

    private static let logger = Logger(subsystem: "com.babegetthis.ios", category: "AuthStateManager")

    init(tokenStore: TokenStore, notificationCenter: NotificationCenter = .default) {
        self.tokenStore = tokenStore
        self.notificationCenter = notificationCenter
        storedUserName = tokenStore.userName()
        storedUserEmail = tokenStore.userEmail()
    }

    var authState: AuthState {
        access(keyPath: \.authState)
        return lock.withLock { storedAuthState }
    }

    /// The signed-in user's display name, or nil when logged out. Separate from
    /// `authState` (which only carries the id) so the UI follows login, logout and edits.
    var userName: String? {
        access(keyPath: \.userName)
        return lock.withLock { storedUserName }
    }

    /// The signed-in user's email. Two accounts can share a display name, so the
    /// profile screen must react to the email on its own.
    var userEmail: String? {
        access(keyPath: \.userEmail)
        return lock.withLock { storedUserEmail }
    }

    /// Whose lists this device shows: the account while signed in or after a lost
    /// session, nobody (guest lists) when signed out or still loading.
    var dataOwnerId: String? { authState.ownerId }

    /// Server work needs a live session, not just a known user: after a lost session
    /// the user id is still stored, but a push or share would only 401.
    var liveSessionUserId: String? {
        if case .authenticated(let userId) = authState { userId } else { nil }
    }

    // MARK: - Transitions

    /// Call once when the app starts. If the Keychain can't be read yet (a launch before the
    /// first unlock after a reboot), stays `.loading` and retries when protected data becomes
    /// available, instead of reading "no user" and signing a signed-in user out of the UI.
    func initialize() {
        lock.withLock {
            let stored: StoredIdentity
            do {
                stored = try tokenStore.restore()
            } catch {
                Self.logger.error("Token store unreadable at launch, waiting for unlock: \(String(describing: error), privacy: .public)")
                waitForProtectedData()
                return
            }
            stopWaitingForProtectedData()
            let state: AuthState = if let userId = stored.userId {
                stored.token == nil ? .sessionExpired(userId: userId) : .authenticated(userId: userId)
            } else {
                .unauthenticated
            }
            setState(state)
            setUserName(stored.userName)
            setUserEmail(stored.userEmail)
        }
    }

    private func waitForProtectedData() {
        guard protectedDataObserver == nil else { return }
        protectedDataObserver = notificationCenter.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.retryInitialize()
        }
    }

    private func stopWaitingForProtectedData() {
        if let observer = protectedDataObserver {
            notificationCenter.removeObserver(observer)
            protectedDataObserver = nil
        }
    }

    /// Only a restore still pending counts: a login in the meantime already settled the state.
    private func retryInitialize() {
        let pending = lock.withLock { storedAuthState == .loading }
        if pending {
            initialize()
        } else {
            lock.withLock { stopWaitingForProtectedData() }
        }
    }

    /// After a successful login or register: persist everything so it survives restarts.
    func login(token: String, userId: String, userName: String, userEmail: String) {
        lock.withLock {
            tokenStore.saveToken(token)
            tokenStore.saveUserId(userId)
            tokenStore.saveUserName(userName)
            tokenStore.saveUserEmail(userEmail)
            setState(.authenticated(userId: userId))
            setUserName(userName)
            setUserEmail(userEmail)
        }
    }

    /// Supabase rotates the access token in the background. Persist just the token
    /// (no state or name change) so later requests stop sending the stale one.
    func refreshToken(_ token: String) {
        tokenStore.saveToken(token)
    }

    /// The session is gone but the user never signed out. Keeps the user id (and with
    /// it the account's lists) and drops only the dead token. A no-op when no user id
    /// is stored, so it can never undo an explicit sign-out, which fires the same event
    /// when it clears the Supabase session. While loading, only storage changes and
    /// `initialize()` derives `.sessionExpired` from it.
    func expireSession() {
        lock.withLock {
            guard let userId = tokenStore.userId() else { return }
            tokenStore.clearToken()
            if storedAuthState != .loading {
                setState(.sessionExpired(userId: userId))
            }
        }
    }

    /// Explicit sign-out and account deletion only.
    func logout() {
        lock.withLock {
            tokenStore.clear()
            setState(.unauthenticated)
            setUserName(nil)
            setUserEmail(nil)
        }
    }

    /// Update just the cached display name (after a profile edit), so every
    /// local-storage write stays behind this one class.
    func updateName(_ name: String) {
        lock.withLock {
            tokenStore.saveUserName(name)
            setUserName(name)
        }
    }

    /// The cached email, if any: a fallback when building a user.
    func currentEmail() -> String? {
        tokenStore.userEmail()
    }

    // MARK: - Change streams

    /// Calls `handler` with the data owner each time it changes, starting with the
    /// current one. `.loading` is skipped so nothing renders guest lists for the
    /// instant before `initialize()` runs. Handlers run synchronously on the thread
    /// making the change; keep them short.
    func observeDataOwner(_ handler: @escaping @Sendable (String?) -> Void) -> AuthStateSubscription {
        lock.withLock {
            let lastEmitted = LockedBox<String??>(nil) // .none: nothing emitted yet
            let onState: @Sendable (AuthState) -> Void = { state in
                guard state != .loading else { return }
                let owner = state.ownerId
                if case .some(let previous) = lastEmitted.value, previous == owner { return }
                lastEmitted.value = .some(owner)
                handler(owner)
            }
            onState(storedAuthState)
            return addObserver(onState)
        }
    }

    /// Calls `handler` each time an account is signed out (explicitly or by deleting
    /// it), which takes its lists off the phone, so the app goes back to Welcome.
    /// A lost session keeps the lists and does not count.
    func observeSignOuts(_ handler: @escaping @Sendable () -> Void) -> AuthStateSubscription {
        lock.withLock {
            let previous = LockedBox<AuthState?>(storedAuthState == .loading ? nil : storedAuthState)
            return addObserver { state in
                guard state != .loading else { return }
                let wasOwned = previous.value?.ownerId != nil
                previous.value = state
                if wasOwned, state == .unauthenticated { handler() }
            }
        }
    }

    /// `observeDataOwner` as an async sequence.
    var dataOwner: AsyncStream<String?> {
        AsyncStream { continuation in
            let subscription = observeDataOwner { continuation.yield($0) }
            continuation.onTermination = { _ in subscription.cancel() }
        }
    }

    /// `observeSignOuts` as an async sequence.
    var signOuts: AsyncStream<Void> {
        AsyncStream { continuation in
            let subscription = observeSignOuts { continuation.yield(()) }
            continuation.onTermination = { _ in subscription.cancel() }
        }
    }

    // MARK: - Private (call with the lock held)

    private func setState(_ state: AuthState) {
        // Like a StateFlow: an unchanged value notifies nobody.
        guard state != storedAuthState else { return }
        withMutation(keyPath: \.authState) { storedAuthState = state }
        for observer in observers.values {
            observer(state)
        }
    }

    private func setUserName(_ name: String?) {
        guard name != storedUserName else { return }
        withMutation(keyPath: \.userName) { storedUserName = name }
    }

    private func setUserEmail(_ email: String?) {
        guard email != storedUserEmail else { return }
        withMutation(keyPath: \.userEmail) { storedUserEmail = email }
    }

    private func addObserver(_ observer: @escaping @Sendable (AuthState) -> Void) -> AuthStateSubscription {
        let id = UUID()
        observers[id] = observer
        return AuthStateSubscription { [weak self] in
            guard let self else { return }
            lock.withLock { _ = self.observers.removeValue(forKey: id) }
        }
    }
}

/// Keeps an `AuthStateManager` observation alive; cancelled explicitly or on deinit.
final class AuthStateSubscription: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?

    init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    deinit { cancel() }

    func cancel() {
        let action = lock.withLock {
            defer { onCancel = nil }
            return onCancel
        }
        action?()
    }
}

/// Per-observer state, only touched under the manager's lock.
private final class LockedBox<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
