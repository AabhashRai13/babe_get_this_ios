import Foundation

// Port of Android `core/sync/data/repository/ShareRepository.kt`.
//
// The two invite-flow entry points: share (owner side) and join (partner
// side). Everything after these runs through SyncEngine like any other edit.

/// The list rows share() reads and writes. ShoppingListDao in the app.
protocol ShareListStore: Sendable {
    /// Sync-internal read with no tombstone filter.
    func listRaw(id: String) async throws -> ShoppingListRecord?
    /// A targeted UPDATE of the code column only.
    func setShareCode(id: String, code: String) async throws
}

/// The engine calls share() and join() make. SyncEngine in the app.
protocol ShareSyncing: Sendable {
    func push() async throws -> Result<Void, AppError>
    func fullCatchUp(listId: String) async throws -> Result<Void, AppError>
}

extension ShoppingListDao: ShareListStore {}
extension SyncEngine: ShareSyncing {}

struct ShareRepository: Sendable {
    /// Picks an index in `0..<upperBound`. Injected so tests can fix the codes
    /// (Android injects a `kotlin.random.Random`).
    typealias RandomIndex = @Sendable (_ upperBound: Int) -> Int

    // Matches the join RPC's normalisation: uppercase, and no 0/O/1/I — they
    // read ambiguously in a texted code. 32^6 ≈ 1e9 codes; the DB unique
    // constraint backstops the astronomically unlikely collision (share()
    // fails, retry generates a fresh code).
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let codeLength = 6

    private let lists: any ShareListStore
    private let remote: any SharedListRemote
    private let syncEngine: any ShareSyncing
    private let currentUserId: @Sendable () -> String?
    private let safeCall: SafeCall
    private let randomIndex: RandomIndex

    init(
        lists: any ShareListStore,
        remote: any SharedListRemote,
        syncEngine: any ShareSyncing,
        currentUserId: @escaping @Sendable () -> String?,
        safeCall: SafeCall,
        randomIndex: @escaping RandomIndex = { Int.random(in: 0..<$0) }
    ) {
        self.lists = lists
        self.remote = remote
        self.syncEngine = syncEngine
        self.currentUserId = currentUserId
        self.safeCall = safeCall
        self.randomIndex = randomIndex
    }

    // Returns the list's share code, generating one on first share. The list
    // already syncs as an account list (docs/technical-decisions/008), so
    // sharing is just giving it a code: make sure the row is on the server,
    // then set the code there. Server first, local second: if that fails the
    // list stays unshared and share() is simply retried with a fresh code.
    func share(listId: String) async throws -> Result<String, AppError> {
        try await safeCall {
            guard let list = try await lists.listRaw(id: listId) else {
                throw AppErrorException(.notFound("That list no longer exists."))
            }
            // Codes are static per list: re-opening the share dialog shows the
            // same one, so a code texted last week keeps working.
            if let code = list.shareCode { return code }
            guard currentUserId() != nil else { throw AppErrorException(.auth("Sign in to share lists.")) }

            // A list made offline may not have reached the server yet. The push
            // uploads its items too; its failure is read off onServer below.
            if !list.onServer { _ = try await syncEngine.push() }
            guard try await lists.listRaw(id: listId)?.onServer == true else {
                throw AppErrorException(.network("Couldn't share — check your connection."))
            }

            // The server answers with the code it actually holds: if this list was
            // already shared (another phone, or an earlier attempt that died before
            // saving locally), the write-once trigger kept that code — adopt it.
            guard let code = try await remote.setShareCode(listId: listId, code: generateCode()) else {
                throw AppErrorException(.unknown())
            }
            // A targeted UPDATE: never a REPLACE (which cascade-deletes the
            // items), and never a stale whole-row write over concurrent edits.
            try await lists.setShareCode(id: listId, code: code)
            return code
        }
    }

    // Enter a code → become a member → land the full replica in the database.
    // The pull is a FULL catch-up (sync point dropped first): on a first join
    // that's simply the initial pull, and on a re-join it refreshes the
    // existing replica instead of silently no-oping from an already-current
    // high-water mark — re-entering the code is also the user's recovery
    // path when a replica has gone bad.
    func join(code: String) async throws -> Result<String, AppError> {
        try await safeCall {
            guard let listId = try await remote.joinListByCode(code.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                throw AppErrorException(.notFound("That code didn't match any list."))
            }
            switch try await syncEngine.fullCatchUp(listId: listId) {
            case .failure(let error): throw AppErrorException(error)
            case .success: return listId
            }
        }
    }

    private func generateCode() -> String {
        String((0..<Self.codeLength).map { _ in Self.alphabet[randomIndex(Self.alphabet.count)] })
    }
}
