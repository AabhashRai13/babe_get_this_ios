import Foundation

// Port of Android `core/sync/data/repository/SyncEngine.kt`, minus the Got This
// hooks (out of iOS v1).
//
// The sync side-process: pushes dirty GRDB rows up, applies server rows down.
// Nothing in the UI layer knows this type exists: remote changes land as
// ordinary database writes and the existing observations redraw.
//
// Conflict model is "last write to REACH THE SERVER wins": the server stamps
// updated_at on every write, incoming rows carry that stamp into the local
// updatedAt, and a dirty local row always beats incoming data locally because
// its eventual push will out-timestamp whatever it beat. No phone clock is
// ever compared against a server clock to decide a winner.
actor SyncEngine {
    private let listDao: ShoppingListDao
    private let itemDao: ShoppingItemDao
    private let remote: any SharedListRemote
    private let syncPoints: any SyncPointStore
    private let ownership: any ListOwnershipStore
    private let currentUserId: @Sendable () -> String?
    private let safeCall: SafeCall

    init(
        listDao: ShoppingListDao,
        itemDao: ShoppingItemDao,
        remote: any SharedListRemote,
        syncPoints: any SyncPointStore,
        ownership: any ListOwnershipStore,
        currentUserId: @escaping @Sendable () -> String?,
        safeCall: SafeCall
    ) {
        self.listDao = listDao
        self.itemDao = itemDao
        self.remote = remote
        self.syncPoints = syncPoints
        self.ownership = ownership
        self.currentUserId = currentUserId
        self.safeCall = safeCall
    }

    // MARK: - Serial gate

    // One operation at a time. Push, catch-up, the sign-in claim and the
    // sign-out eviction all read and write the same rows, and two of them
    // interleaved undo each other: a catch-up still in flight while sign-out
    // evicts the account's lists would land them again afterwards, and a
    // delete racing a first INSERT could leave a list on the server that this
    // phone has forgotten. The actor alone is not enough: it is reentrant at
    // every await, so this is Android's Mutex. Every public entry point takes
    // it; the *Locked helpers are what runs inside it, so nothing nests.
    private var gateHeld = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []

    private func serially<T>(_ body: () async throws -> T) async rethrows -> T {
        if gateHeld {
            // FIFO hand-off: the releasing operation passes the gate on still held.
            await withCheckedContinuation { gateWaiters.append($0) }
        } else {
            gateHeld = true
        }
        defer {
            if gateWaiters.isEmpty {
                gateHeld = false
            } else {
                gateWaiters.removeFirst().resume()
            }
        }
        return try await body()
    }

    // MARK: - Push

    // Push everything pendingSync that belongs to the signed-in account —
    // every account list, shared or not (docs/technical-decisions/008). Lists
    // strictly before items: the server's creator-membership trigger on `lists`
    // is what makes the item RLS checks pass (see the SQL migration's client
    // contract note). No live session → no-op; the queue just waits.
    func push() async throws -> Result<Void, AppError> {
        try await safeCall {
            try await serially { try await pushLocked() }
        }
    }

    private func pushLocked() async throws {
        // A list deleted before it ever reached the server has nothing to tell
        // anyone. Uploading its tombstone would create a server row (plus a
        // membership row and its items) that no pass ever purges and every
        // discovery returns, so it goes here instead — under the gate, so it
        // can't race the INSERT that would have put it on the server. Needs no
        // session: it is outbox housekeeping, and it keeps the sign-out
        // warning honest for a session that has expired.
        try await listDao.deleteNeverSentDeletedLists()
        guard let userId = currentUserId() else { return }
        let lists = try await listDao.pendingAccountLists(accountId: userId)
        // A brand-new row must be a plain INSERT — an upsert of it fails RLS
        // (SharedListRemote.insertList). "Already there" (false) means an
        // earlier push landed before the app could record it; the row may have
        // changed since, so it joins the upsert below like any row already on
        // the server, instead of the server keeping that first version.
        var upserts = lists.filter(\.onServer)
        for list in lists where !list.onServer {
            if try await !remote.insertList(list.syncLocal.toRow(createdBy: userId)) {
                upserts.append(list)
            }
            try await listDao.markListOnServer(id: list.id)
        }
        if !upserts.isEmpty {
            try await remote.upsertLists(upserts.map { $0.syncLocal.toRow(createdBy: userId) })
        }
        // Guarded per-row clear: a row edited again mid-push keeps its
        // flag (updatedAt no longer matches) and re-pushes next kick.
        for list in lists {
            try await listDao.markListSynced(id: list.id, updatedAt: list.updatedAt)
        }
        let items = try await itemDao.pendingSyncItemsForAccount(userId)
        if !items.isEmpty {
            // Never carries picked_up_at: iOS v1 acts as a pre-Got-This client.
            try await remote.upsertItems(items.map { $0.syncLocal.toRow() })
            for item in items {
                try await itemDao.markItemSynced(id: item.id, updatedAt: item.updatedAt)
            }
        }
    }

    // MARK: - Outbox

    // Anything of this account's still waiting to reach the server — the rows
    // push would send, which eviction deletes. Rows push can never send (a
    // released first-run claim, another account's leftovers) aren't counted:
    // a warning about them could never be cleared by going online.
    func hasUnsyncedChanges(accountId: String) async throws -> Bool {
        let lists = try await listDao.countPendingAccountLists(accountId: accountId)
        let items = try await itemDao.countPendingSyncItemsForAccount(accountId)
        return lists + items > 0
    }
}
