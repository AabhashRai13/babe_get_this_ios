import Foundation
@testable import BabeGetThis

// The share-code knobs of Android's `FakeSharedListRemote` (`testing/SyncFakes.kt`)
// that the shared iOS fake doesn't have yet. Everything else forwards to the
// shared `FakeSharedListRemote`, so the real SyncEngine runs against it as usual.
final class ShareTestRemote: SharedListRemote, @unchecked Sendable {
    let inner = FakeSharedListRemote()

    private let lock = NSLock()
    private var _shareCodeRequests: [(listId: String, code: String)] = []
    private var _serverShareCode: String?
    private var _shareCodeRowMissing = false
    private var _shareCodeClashes = 0

    var shareCodeRequests: [(listId: String, code: String)] { lock.withLock { _shareCodeRequests } }
    var serverShareCode: String? {
        get { lock.withLock { _serverShareCode } }
        set { lock.withLock { _serverShareCode = newValue } }
    }
    var shareCodeRowMissing: Bool {
        get { lock.withLock { _shareCodeRowMissing } }
        set { lock.withLock { _shareCodeRowMissing = newValue } }
    }
    /// How many of the next setShareCode calls hit the unique constraint on share_code.
    var shareCodeClashes: Int {
        get { lock.withLock { _shareCodeClashes } }
        set { lock.withLock { _shareCodeClashes = newValue } }
    }

    func setShareCode(listId: String, code: String) async throws -> String? {
        if inner.failUpserts { throw FakeRemoteFailure() }
        return try lock.withLock {
            _shareCodeRequests.append((listId, code))
            if _shareCodeClashes > 0 {
                _shareCodeClashes -= 1
                throw AppErrorException(.server(code: 409, message: "duplicate share_code"))
            }
            if _shareCodeRowMissing { return nil }
            return _serverShareCode ?? code
        }
    }

    func insertList(_ row: ListRow) async throws -> Bool { try await inner.insertList(row) }
    func upsertLists(_ rows: [ListRow]) async throws { try await inner.upsertLists(rows) }
    func upsertItems(_ rows: [ItemRow]) async throws { try await inner.upsertItems(rows) }
    func fetchList(listId: String, sinceIso: String?) async throws -> [ListRow] {
        try await inner.fetchList(listId: listId, sinceIso: sinceIso)
    }
    func fetchItems(listId: String, sinceIso: String?) async throws -> [ItemRow] {
        try await inner.fetchItems(listId: listId, sinceIso: sinceIso)
    }
    func fetchAccountItems(sinceIso: String?) async throws -> [ItemRow] {
        try await inner.fetchAccountItems(sinceIso: sinceIso)
    }
    func fetchAllLists() async throws -> [ListRow] { try await inner.fetchAllLists() }
    func joinListByCode(_ code: String) async throws -> String? { try await inner.joinListByCode(code) }
    func changes(listId: String) -> AsyncThrowingStream<Void, any Error> { inner.changes(listId: listId) }
}

/// Deterministic stand-in for Android's `Random(seed = 7)`: a small LCG, so
/// every run draws the same codes and consecutive draws differ.
final class ShareTestRandom: @unchecked Sendable {
    private let lock = NSLock()
    private var state: UInt64

    init(seed: UInt64 = 7) { state = seed }

    func nextIndex(_ upperBound: Int) -> Int {
        lock.withLock {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(upperBound))
        }
    }
}
