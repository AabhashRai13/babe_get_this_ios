import Foundation
import Network
import Observation

/// Every auth state, starting with the current one, then each change (Android's
/// `authStateManager.authState` StateFlow, collected).
protocol AuthStateStream: AnyObject, Sendable {
    func observeAuthStates(_ handler: @escaping @Sendable (AuthState) -> Void) -> AuthStateSubscription
}

extension AuthStateManager: AuthStateStream {
    /// Follows `authState` through Observation, which `AuthStateManager` publishes on the main
    /// thread. Like a StateFlow, an equal value is not repeated and a burst of changes may be
    /// seen as its last value.
    func observeAuthStates(_ handler: @escaping @Sendable (AuthState) -> Void) -> AuthStateSubscription {
        let watcher = AuthStateWatcher(manager: self, handler: handler)
        watcher.arm()
        return AuthStateSubscription { watcher.cancel() }
    }
}

private final class AuthStateWatcher: @unchecked Sendable {
    private let manager: AuthStateManager
    private let handler: @Sendable (AuthState) -> Void
    private let lock = NSLock()
    private var last: AuthState?
    private var cancelled = false

    init(manager: AuthStateManager, handler: @escaping @Sendable (AuthState) -> Void) {
        self.manager = manager
        self.handler = handler
    }

    func arm() {
        guard !lock.withLock({ cancelled }) else { return }
        let state = withObservationTracking {
            manager.authState
        } onChange: { [self] in
            // Called as the change is published; re-read (and re-arm) once it has landed.
            DispatchQueue.main.async { self.arm() }
        }
        let isNew = lock.withLock {
            guard !cancelled, state != last else { return false }
            last = state
            return true
        }
        if isNew { handler(state) }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

/// Calls back when a usable network becomes available, including at once on start if one
/// already is (Android `registerDefaultNetworkCallback` + `onAvailable`).
protocol NetworkAvailabilitySource: AnyObject, Sendable {
    func start(onAvailable: @escaping @Sendable () -> Void)
}

/// `NWPathMonitor` behind `NetworkAvailabilitySource`: fires on each move to a satisfied path.
/// Its own monitor, so `NetworkMonitor`'s synchronous reads stay as they are.
final class SystemNetworkAvailability: NetworkAvailabilitySource, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var wasSatisfied = false

    init() {}

    deinit {
        monitor.cancel()
    }

    func start(onAvailable: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            let becameAvailable = lock.withLock {
                defer { wasSatisfied = satisfied }
                return satisfied && !wasSatisfied
            }
            if becameAvailable { onAvailable() }
        }
        monitor.start(queue: DispatchQueue(label: "com.babegetthis.ios.sync-trigger-network"))
    }
}
