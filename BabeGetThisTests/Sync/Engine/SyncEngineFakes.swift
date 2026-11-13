import Foundation
@testable import BabeGetThis

// Port of Android `testing/SyncFakes.kt`: one knobbed fake remote shared by the
// SyncEngine test classes, plus in-memory sync stores.

struct FakeRemoteFailure: Error {}

final class FakeSharedListRemote: SharedListRemote, @unchecked Sendable {
    private let lock = NSLock()

    private var _upsertedLists: [ListRow] = []
    private var _upsertedItems: [ItemRow] = []
    private var _insertedLists: [ListRow] = []
    private var _fetchedListIds: [String] = []
    private var _itemFetchListIds: [String] = []
    private var _lastListSince: String?
    private var _lastItemSince: String?
    private var _listRows: [ListRow] = []
    private var _itemRows: [ItemRow] = []
    private var _failUpserts = false
    private var _failItemUpserts = false
    private var _failFetches = false
    private var _listAlreadyExists = false
    private var _onUpsertItems: @Sendable () async throws -> Void = {}
    private var _joinResult: String?
    private var _joinCalledWith: String?

    var upsertedLists: [ListRow] { locked { _upsertedLists } }
    var upsertedItems: [ItemRow] { locked { _upsertedItems } }
    var insertedLists: [ListRow] { locked { _insertedLists } }
    var fetchedListIds: [String] { locked { _fetchedListIds } }
    var itemFetchListIds: [String] { locked { _itemFetchListIds } }
    var lastListSince: String? { locked { _lastListSince } }
    var lastItemSince: String? { locked { _lastItemSince } }
    var joinCalledWith: String? { locked { _joinCalledWith } }

    var listRows: [ListRow] {
        get { locked { _listRows } }
        set { locked { _listRows = newValue } }
    }
    var itemRows: [ItemRow] {
        get { locked { _itemRows } }
        set { locked { _itemRows = newValue } }
    }
    var failUpserts: Bool {
        get { locked { _failUpserts } }
        set { locked { _failUpserts = newValue } }
    }
    var failItemUpserts: Bool {
        get { locked { _failItemUpserts } }
        set { locked { _failItemUpserts = newValue } }
    }
    var failFetches: Bool {
        get { locked { _failFetches } }
        set { locked { _failFetches = newValue } }
    }
    var listAlreadyExists: Bool {
        get { locked { _listAlreadyExists } }
        set { locked { _listAlreadyExists = newValue } }
    }
    var onUpsertItems: @Sendable () async throws -> Void {
        get { locked { _onUpsertItems } }
        set { locked { _onUpsertItems = newValue } }
    }
    var joinResult: String? {
        get { locked { _joinResult } }
        set { locked { _joinResult = newValue } }
    }

    func insertList(_ row: ListRow) async throws -> Bool {
        try locked {
            if _failUpserts { throw FakeRemoteFailure() }
            if _listAlreadyExists { return false }
            _insertedLists.append(row)
            return true
        }
    }

    func setShareCode(listId: String, code: String) async throws -> String? {
        if failUpserts { throw FakeRemoteFailure() }
        return code
    }

    func upsertLists(_ rows: [ListRow]) async throws {
        try locked {
            if _failUpserts { throw FakeRemoteFailure() }
            _upsertedLists += rows
        }
    }

    func upsertItems(_ rows: [ItemRow]) async throws {
        if failUpserts || failItemUpserts { throw FakeRemoteFailure() }
        try await onUpsertItems()
        locked { _upsertedItems += rows }
    }

    func fetchList(listId: String, sinceIso: String?) async throws -> [ListRow] {
        try locked {
            if _failFetches { throw FakeRemoteFailure() }
            _fetchedListIds.append(listId)
            _lastListSince = sinceIso
            return _listRows.filter { $0.id == listId }
        }
    }

    func fetchItems(listId: String, sinceIso: String?) async throws -> [ItemRow] {
        try locked {
            if _failFetches { throw FakeRemoteFailure() }
            _itemFetchListIds.append(listId)
            _lastItemSince = sinceIso
            return _itemRows.filter { $0.listId == listId }
        }
    }

    func fetchAccountItems(sinceIso: String?) async throws -> [ItemRow] {
        try locked {
            if _failFetches { throw FakeRemoteFailure() }
            return _itemRows.filter { sinceIso == nil || ($0.updatedAt ?? "") >= sinceIso! }
        }
    }

    func fetchAllLists() async throws -> [ListRow] {
        try locked {
            if _failFetches { throw FakeRemoteFailure() }
            return _listRows
        }
    }

    func joinListByCode(_ code: String) async throws -> String? {
        locked {
            _joinCalledWith = code
            return _joinResult
        }
    }

    func changes(listId: String) -> AsyncThrowingStream<Void, any Error> {
        AsyncThrowingStream { _ in }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

final class FakeSyncPointStore: SyncPointStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _points: [String: String] = [:]

    var points: [String: String] { lock.withLock { _points } }

    func get(listId: String) -> String? { lock.withLock { _points[listId] } }
    func set(listId: String, iso: String) { lock.withLock { _points[listId] = iso } }
    func remove(listId: String) { lock.withLock { _ = _points.removeValue(forKey: listId) } }
    func clear() { lock.withLock { _points.removeAll() } }
}

final class FakeListOwnershipStore: ListOwnershipStore, @unchecked Sendable {
    private let lock = NSLock()
    private var notice = 0
    private var _migrated = false
    private var locks: Set<String> = []
    private var unverified: Set<String> = []

    var migrated: Bool {
        get { lock.withLock { _migrated } }
        set { lock.withLock { _migrated = newValue } }
    }

    var adoptionNotice: Int { lock.withLock { notice } }

    func adoptionNoticeUpdates() -> AsyncStream<Int> {
        let current = adoptionNotice
        return AsyncStream { continuation in
            continuation.yield(current)
            continuation.finish()
        }
    }

    func setAdoptionNotice(_ count: Int) { lock.withLock { notice = count } }
    func isAccountListsMigrated() -> Bool { migrated }
    func markAccountListsMigrated() { migrated = true }
    func lockedListIds() -> Set<String> { lock.withLock { locks } }

    func rememberLock(listId: String, locked: Bool) {
        lock.withLock {
            if locked { locks.insert(listId) } else { locks.remove(listId) }
        }
    }

    func forgetAllLocks() { lock.withLock { locks.removeAll() } }
    func unverifiedListIds() -> Set<String> { lock.withLock { unverified } }
    func setUnverifiedListIds(_ ids: Set<String>) { lock.withLock { unverified = ids } }
}
