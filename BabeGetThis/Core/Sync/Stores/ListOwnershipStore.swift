import Foundation

// Small device-local facts about list ownership that must outlive the rows
// they describe (docs/technical-decisions/008). Defaults, not GRDB: eviction
// deletes the rows, and these have to survive it. A protocol so the engine
// and repositories can be tested against a fake, like SyncPointStore.
protocol ListOwnershipStore: Sendable {
    /// Guest lists moved into the account that the user hasn't been told about yet.
    var adoptionNotice: Int { get }
    /// Observable form of `adoptionNotice` (StateFlow on Android): yields the current value first, then each change.
    func adoptionNoticeUpdates() -> AsyncStream<Int>
    func setAdoptionNotice(_ count: Int)

    /// The first claim after the ownership update also takes the existing shared
    /// replicas, which have no recorded owner. Only once.
    func isAccountListsMigrated() -> Bool
    func markAccountListsMigrated()

    /// Ids of lists the user locked on this device. The lock is per-device and
    /// never syncs, so it would be lost when sign-out evicts the list; the list
    /// is re-locked when it comes back.
    func lockedListIds() -> Set<String>
    func rememberLock(listId: String, locked: Bool)
    func forgetAllLocks()

    /// Shared replicas the first claim took without the server confirming the
    /// account is a member. Held until the first successful discovery, which
    /// keeps the ones it returns and releases the rest.
    func unverifiedListIds() -> Set<String>
    func setUnverifiedListIds(_ ids: Set<String>)
}

// Plain UserDefaults, like PrefsSyncPointStore: a counter, a flag and a set of
// list ids, nothing secret.
final class PrefsListOwnershipStore: ListOwnershipStore, @unchecked Sendable {
    static let defaultSuiteName = "list_ownership"

    private enum Key {
        static let adoptionNotice = "adoption_notice"
        static let migrated = "account_lists_migrated"
        static let locked = "locked_list_ids"
        static let unverified = "unverified_list_ids"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var current: Int
    private var continuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.current = defaults.integer(forKey: Key.adoptionNotice)
    }

    convenience init() {
        self.init(defaults: UserDefaults(suiteName: Self.defaultSuiteName) ?? .standard)
    }

    var adoptionNotice: Int {
        lock.withLock { current }
    }

    func adoptionNoticeUpdates() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock {
                continuations[id] = continuation
                continuation.yield(current)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
            }
        }
    }

    func setAdoptionNotice(_ count: Int) {
        lock.withLock {
            defaults.set(count, forKey: Key.adoptionNotice)
            guard count != current else { return }
            current = count
            for continuation in continuations.values { continuation.yield(count) }
        }
    }

    func isAccountListsMigrated() -> Bool {
        defaults.bool(forKey: Key.migrated)
    }

    func markAccountListsMigrated() {
        defaults.set(true, forKey: Key.migrated)
    }

    func lockedListIds() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.locked) ?? [])
    }

    func rememberLock(listId: String, locked: Bool) {
        lock.withLock {
            var ids = lockedListIds()
            if locked { ids.insert(listId) } else { ids.remove(listId) }
            defaults.set(Array(ids).sorted(), forKey: Key.locked)
        }
    }

    func forgetAllLocks() {
        defaults.removeObject(forKey: Key.locked)
    }

    func unverifiedListIds() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.unverified) ?? [])
    }

    func setUnverifiedListIds(_ ids: Set<String>) {
        defaults.set(Array(ids).sorted(), forKey: Key.unverified)
    }
}
