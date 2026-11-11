import Foundation

// Per-list high-water mark: the newest server updated_at (ISO string) we've
// applied. Catch-up queries resume from here. Stored as the raw ISO string,
// since Supabase always returns UTC in one format, so lexicographic max == newest.
protocol SyncPointStore: Sendable {
    func get(listId: String) -> String?
    func set(listId: String, iso: String)

    /// Drop one list's mark so the next catchUp pulls everything (join()'s refresh-on-rejoin path).
    func remove(listId: String)

    /// Wipe all marks: part of shared-replica eviction on explicit sign-out.
    func clear()
}

// Plain UserDefaults (not encrypted, these are just timestamps), keyed by list id,
// in its own suite so clear() cannot touch unrelated preferences.
final class PrefsSyncPointStore: SyncPointStore, @unchecked Sendable {
    static let defaultSuiteName = "sync_points"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    convenience init() {
        self.init(defaults: UserDefaults(suiteName: Self.defaultSuiteName) ?? .standard)
    }

    func get(listId: String) -> String? {
        defaults.string(forKey: listId)
    }

    func set(listId: String, iso: String) {
        defaults.set(iso, forKey: listId)
    }

    func remove(listId: String) {
        defaults.removeObject(forKey: listId)
    }

    func clear() {
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
    }
}
