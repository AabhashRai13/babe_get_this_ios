import Foundation
@testable import BabeGetThis

/// Records what the trigger asked of the engine. `onAuthState` answers from `liveStates`.
final class TriggerFakeEngine: SyncTriggerEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var pushes = 0
    private var catchUps = 0
    private var listCatchUps: [String] = []
    private var states: [AuthState] = []
    private var live: (AuthState) -> Bool = { _ in false }

    var pushCount: Int { lock.withLock { pushes } }
    var catchUpAccountCount: Int { lock.withLock { catchUps } }
    var catchUpListIds: [String] { lock.withLock { listCatchUps } }
    var authStates: [AuthState] { lock.withLock { states } }

    func answerOnAuthState(_ answer: @escaping (AuthState) -> Bool) {
        lock.withLock { live = answer }
    }

    func push() async throws -> Result<Void, AppError> {
        lock.withLock { pushes += 1 }
        return .success(())
    }

    func catchUpAccount() async throws -> Result<Void, AppError> {
        lock.withLock { catchUps += 1 }
        return .success(())
    }

    func catchUp(listId: String) async throws -> Result<Void, AppError> {
        lock.withLock { listCatchUps.append(listId) }
        return .success(())
    }

    func onAuthState(_ state: AuthState) async -> Bool {
        lock.withLock {
            states.append(state)
            return live(state)
        }
    }
}

/// A `MutableStateFlow<AuthState>` stand-in: replays the current value, then each change.
final class TriggerFakeAuthStates: AuthStateStream, @unchecked Sendable {
    private let lock = NSLock()
    private var current: AuthState
    private var handlers: [UUID: @Sendable (AuthState) -> Void] = [:]

    init(_ initial: AuthState) {
        current = initial
    }

    var value: AuthState {
        get { lock.withLock { current } }
        set {
            let toCall: [@Sendable (AuthState) -> Void] = lock.withLock {
                guard newValue != current else { return [] }
                current = newValue
                return Array(handlers.values)
            }
            toCall.forEach { $0(newValue) }
        }
    }

    func observeAuthStates(_ handler: @escaping @Sendable (AuthState) -> Void) -> AuthStateSubscription {
        let id = UUID()
        let state = lock.withLock {
            handlers[id] = handler
            return current
        }
        handler(state)
        return AuthStateSubscription { [weak self] in
            guard let self else { return }
            lock.withLock { _ = self.handlers.removeValue(forKey: id) }
        }
    }
}

/// Hands back the registered callback, like Robolectric's shadow ConnectivityManager. Nothing
/// fires on its own: each test decides.
final class TriggerFakeNetwork: NetworkAvailabilitySource, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?

    var isStarted: Bool { lock.withLock { callback != nil } }

    func start(onAvailable: @escaping @Sendable () -> Void) {
        lock.withLock { callback = onAvailable }
    }

    func becomeAvailable() {
        lock.withLock { callback }?()
    }
}

/// Keeps every launched task so a test can wait until the trigger has gone quiet
/// (Android's UnconfinedTestDispatcher runs them eagerly instead).
final class TriggerTaskRecorder: SyncTaskLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Task<Void, Never>] = []

    @discardableResult
    func launch(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        let task = Task.detached(operation: operation)
        lock.withLock { pending.append(task) }
        return task
    }

    /// Waits for every task, including ones launched by the tasks it waits for.
    func drain() async {
        while true {
            let batch: [Task<Void, Never>] = lock.withLock {
                defer { pending.removeAll() }
                return pending
            }
            if batch.isEmpty { return }
            for task in batch { await task.value }
        }
    }
}
