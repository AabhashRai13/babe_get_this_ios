import Foundation
import SwiftUI

// Port of Android `core/sync/SyncTrigger.kt`.
//
// Kicks a push + catch-up whenever connectivity returns or the app comes to
// the foreground. Sync deliberately does not run in the background (Android
// resolved its open question to "foreground + connectivity callback"): a
// queued edit waits at most until the next time the user opens the app with
// signal, acceptable for a shopping list. Kicks are cheap and idempotent, so
// double-firing (e.g. registration + first foreground) is harmless: no
// debounce, no timer (TRIG-01).

/// What the trigger needs from `SyncEngine`, so tests drive it without a server.
protocol SyncTriggerEngine: Sendable {
    func push() async throws -> Result<Void, AppError>
    func catchUpAccount() async throws -> Result<Void, AppError>
    func onAuthState(_ state: AuthState) async -> Bool
}

extension SyncEngine: SyncTriggerEngine {}

/// Starts the trigger's fire-and-forget work. Tests swap in one that can wait for it.
protocol SyncTaskLaunching: Sendable {
    @discardableResult
    func launch(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never>
}

struct DetachedSyncTaskLauncher: SyncTaskLaunching {
    @discardableResult
    func launch(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task.detached(operation: operation)
    }
}

final class SyncTrigger: SyncKicking, @unchecked Sendable {
    /// nil while sync is off (test containers, `-sampleData`): every kick is then dropped,
    /// so nothing builds a Supabase client or reaches the network.
    private let engine: @Sendable () async -> (any SyncTriggerEngine)?
    private let launcher: any SyncTaskLaunching
    private let lock = NSLock()
    private var authSubscription: AuthStateSubscription?
    private var network: (any NetworkAvailabilitySource)?
    /// The last auth state's work, so states reach the engine in order, like a collector.
    private var lastAuthWork: Task<Void, Never>?
    private var isForeground = false

    init(engine: @escaping @Sendable () async -> (any SyncTriggerEngine)?,
         launcher: any SyncTaskLaunching = DetachedSyncTaskLauncher()) {
        self.engine = engine
        self.launcher = launcher
    }

    // Push-only: repositories kick this after local edits. Catch-up isn't
    // needed there: the partner's device pulls, ours already has the data.
    func pushSoon() {
        launcher.launch { [engine] in
            _ = try? await engine()?.push()
        }
    }

    func register(authStates: any AuthStateStream, network: any NetworkAvailabilitySource) {
        // Every auth state change first settles who owns the device's lists
        // (claim on sign-in or a lost session), then a live session kicks:
        // discovery is what materialises the account's lists after login, and
        // logging in changes neither foreground state nor connectivity. The
        // stream starts with the current value, which is what claims after an update.
        let subscription = authStates.observeAuthStates { [weak self] state in
            self?.onAuthState(state)
        }
        // Fires at once on registration when a network is already up: that's
        // the app-start kick for free.
        network.start { [weak self] in self?.kick() }
        lock.withLock {
            authSubscription = subscription
            self.network = network
        }
    }

    /// Feed `scenePhase` here. Only background → active is a new foreground: inactive (a
    /// system sheet, the app switcher) passes through without one.
    func scenePhaseChanged(_ phase: ScenePhase) {
        let foregrounded: Bool = lock.withLock {
            switch phase {
            case .active:
                defer { isForeground = true }
                return !isForeground
            case .background:
                isForeground = false
                return false
            default:
                return false
            }
        }
        if foregrounded { kick() }
    }

    private func onAuthState(_ state: AuthState) {
        lock.withLock {
            let previous = lastAuthWork
            lastAuthWork = launcher.launch { [weak self, engine] in
                await previous?.value
                guard let engine = await engine() else { return }
                if await engine.onAuthState(state) { self?.kick() }
            }
        }
    }

    private func kick() {
        launcher.launch { [engine] in
            // Results intentionally dropped: failures stay queued (pendingSync
            // flags / sync points untouched) and the next kick retries.
            guard let engine = await engine() else { return }
            _ = try? await engine.push()
            _ = try? await engine.catchUpAccount()
        }
    }
}
