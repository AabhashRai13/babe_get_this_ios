import Foundation
import GRDB

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
        //
        // A list soft-deleted after the drop above but before the read (UI
        // writes don't take the gate) arrives here as a tombstone that never
        // reached the server. It is skipped and stays pending, with its items,
        // so the next push's drop deletes it. INSERTing it would create the
        // server row this branch exists to avoid. (Android has the same gap
        // between dropNeverSentLists and getPendingAccountLists; see SYNC-04.)
        let neverSentTombstones = Set(lists.filter { !$0.onServer && $0.deletedAt != nil }.map(\.id))
        let sendable = lists.filter { !neverSentTombstones.contains($0.id) }
        var upserts = sendable.filter(\.onServer)
        for list in sendable where !list.onServer {
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
        for list in sendable {
            try await listDao.markListSynced(id: list.id, updatedAt: list.updatedAt)
        }
        let items = try await itemDao.pendingSyncItemsForAccount(userId)
            .filter { !neverSentTombstones.contains($0.listId) }
        if !items.isEmpty {
            // Never carries picked_up_at: iOS v1 acts as a pre-Got-This client.
            try await remote.upsertItems(items.map { $0.syncLocal.toRow() })
            for item in items {
                try await itemDao.markItemSynced(id: item.id, updatedAt: item.updatedAt)
            }
        }
    }

    // MARK: - Catch-up

    // Fetch everything changed in one list since its sync point and land it in
    // the database. Used for an open list (and on every realtime event of a
    // shared one): realtime events don't carry data anywhere — they just
    // trigger this. Idempotent by construction, so gte-refetch of the newest
    // known row is harmless. No live session → nothing to ask.
    func catchUp(listId: String) async throws -> Result<Void, AppError> {
        try await safeCall {
            try await serially { try await catchUpLocked(listId: listId) }
        }
    }

    private func catchUpLocked(listId: String) async throws {
        guard let userId = currentUserId() else { return }
        let since = syncPoints.get(listId: listId)
        let listRows = try await remote.fetchList(listId: listId, sinceIso: since)
        let itemRows = try await remote.fetchItems(listId: listId, sinceIso: since)
        try await apply(userId: userId, listRows: listRows, itemRows: itemRows)
        // Advance the high-water mark only AFTER a full successful apply — a
        // failure above leaves it untouched and the next catch-up refetches.
        let newest = (listRows.compactMap(\.updatedAt) + itemRows.compactMap(\.updatedAt)).max()
        if let newest { syncPoints.set(listId: listId, iso: newest) }
    }

    // Full re-pull of one list: drop the high-water mark, then catch up from
    // scratch. join() uses this so re-joining REFRESHES the replica (spec:
    // "joining twice is idempotent — the existing replica is refreshed") —
    // plain catchUp starts from the stored sync point, which on a re-join is
    // already current and silently no-ops. Also the user-driven recovery road
    // if a replica ever goes bad: leave + re-enter the code.
    //
    // The removal runs inside the gate: outside it, a catch-up already in
    // flight could set the old mark again after the removal, and the "full"
    // pull would start from it. (Android removes it outside its Mutex; see
    // SYNC-08.)
    func fullCatchUp(listId: String) async throws -> Result<Void, AppError> {
        try await safeCall {
            try await serially {
                syncPoints.remove(listId: listId)
                try await catchUpLocked(listId: listId)
            }
        }
    }

    // MARK: - Apply

    // One write transaction for the whole apply. The repositories write the
    // same database without taking the gate, so a read-then-write in separate
    // transactions lets a local edit (a tick, a rename) commit in between and
    // be overwritten with pendingSync = 0: lost on screen and never pushed.
    // Inside one transaction the skip decision and the write see the same
    // state: an edit that commits first makes the row dirty and wins; one that
    // commits after lands on top. It also makes the apply all-or-nothing, so a
    // failure leaves the sync point and every row as they were (SYNC-07).
    // (Android reads and writes in separate Room calls; see SYNC-10.)
    private func apply(userId: String, listRows: [ListRow], itemRows: [ItemRow]) async throws {
        let lockedIds = ownership.lockedListIds()
        try await listDao.writer.write { db in
            try Self.applyLists(db, userId: userId, rows: listRows, lockedIds: lockedIds)
            try Self.applyItems(db, rows: itemRows)
        }
    }

    private static func applyLists(_ db: Database, userId: String, rows: [ListRow], lockedIds: Set<String>) throws {
        for row in rows {
            let local = try ShoppingListRecord.fetchOne(db, key: row.id)
            // The deletion of a list this phone never had: nothing to hide, so
            // nothing to store.
            if local == nil && row.deletedAt != nil { continue }
            // A replica with no owner (its session was lost before lists had
            // owners) is claimed the moment the server returns it for this
            // account — that answer is the proof of membership. Even when the
            // local row is dirty and the incoming data loses below.
            if let local, local.accountId == nil { try ShoppingListDao.claimList(db, id: row.id, accountId: userId) }
            if try shouldSkip(localDirty: local?.pendingSync, localUpdatedAt: local?.updatedAt, incomingIso: row.updatedAt) {
                continue
            }
            let record = ShoppingListRecord(
                syncLocal: try row.toRecord(local: local?.syncLocal, accountId: userId, lockedIds: lockedIds))
            // UPDATE, not INSERT OR REPLACE, when the row already exists: REPLACE
            // is DELETE + INSERT in SQLite, which fires shopping_items' ON DELETE
            // CASCADE and hard-deletes every item of the list. A single renamed
            // list arriving from a peer would wipe that list's items on every
            // device (including the one that made the rename, once its own push
            // echoed back) — unrecoverably, since the rows are gone rather than
            // tombstoned and the sync point has already moved past them.
            if local == nil {
                try record.insert(db)
            } else {
                try record.update(db)
            }
        }
    }

    private static func applyItems(_ db: Database, rows: [ItemRow]) throws {
        for row in rows {
            // FK guard: an item whose list isn't in the database yet can't be
            // inserted (CASCADE FK). The list row lands via the same catch-up
            // that brought the item, so the next pass picks the item up.
            if try !ShoppingListRecord.exists(db, key: row.listId) { continue }
            let local = try ShoppingItemRecord.fetchOne(db, key: row.id)
            if local == nil && row.deletedAt != nil { continue }
            if try shouldSkip(localDirty: local?.pendingSync, localUpdatedAt: local?.updatedAt, incomingIso: row.updatedAt) {
                continue
            }
            let record = ShoppingItemRecord(syncLocal: try row.toRecord(local: local?.syncLocal))
            if local == nil {
                // Same upsert as ShoppingItemDao.insertItem (SYNC-11).
                try record.upsert(db)
            } else {
                try record.update(db)
            }
        }
    }

    // Incoming loses when: the local row is dirty (our pending push will
    // out-timestamp it at the server), or the incoming stamp is no newer than
    // what we already applied (the same row again — discovery returns every
    // row on every pass — or a stale/out-of-order fetch).
    private static func shouldSkip(localDirty: Bool?, localUpdatedAt: Int64?, incomingIso: String?) throws -> Bool {
        guard let incomingIso else { return true } // defensive: server rows always carry it
        guard let localDirty, let localUpdatedAt else { return false } // no local row → apply
        return try localDirty || incomingIso.isoToMillis() <= localUpdatedAt
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
