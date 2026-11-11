import Foundation

/// Thin seam over Supabase so SyncEngine is testable with a fake. Port of Android `SharedListRemote.kt`.
/// No logic belongs here — anything with a branch goes in the engine. The one exception is paging:
/// PostgREST caps every response (Supabase's default max_rows is 1000) and silently cuts the rest, so every
/// multi-row read here returns the COMPLETE result, however many requests that takes. Callers never see a page.
///
/// Errors are thrown raw (PostgrestError, URLError, ...); repositories map them through `SafeCall`.
protocol SharedListRemote: Sendable {
    /// Plain INSERT for the FIRST share of a list — deliberately not upsert: Postgres evaluates the upsert's
    /// update-arm policy (is_list_member) against the incoming row BEFORE the creator-membership AFTER-INSERT
    /// trigger has run, so upserting a brand-new list always fails RLS (42501).
    /// Returns false when the row already exists (a previous share reached the server but never persisted
    /// locally) — caller recovers via fetchList.
    func insertList(_ row: ListRow) async throws -> Bool

    /// Shares a list that already syncs: sets its code unless it has one (the server's write-once trigger
    /// keeps the first) and returns the code the server now holds. Nil when the row isn't visible to this
    /// session. A targeted UPDATE rather than an upsert of the whole row, so sharing can never clobber a newer
    /// name or deletion from another phone.
    func setShareCode(listId: String, code: String) async throws -> String?

    /// Upsert is fine for every later push: the row exists, membership exists.
    func upsertLists(_ rows: [ListRow]) async throws

    func upsertItems(_ rows: [ItemRow]) async throws

    /// `sinceIso` nil = full pull (first join). Otherwise rows with updated_at >= since — gte, not gt:
    /// re-fetching the newest already-seen row is harmless (apply is idempotent) and closes the
    /// equal-timestamp gap.
    func fetchList(listId: String, sinceIso: String?) async throws -> [ListRow]

    func fetchItems(listId: String, sinceIso: String?) async throws -> [ItemRow]

    /// Account-wide item catch-up: every item the current session may see (RLS scopes it to the account's
    /// lists, like fetchAllLists) changed since `sinceIso` (nil = everything).
    func fetchAccountItems(sinceIso: String?) async throws -> [ItemRow]

    /// Discovery: every list row the current session may see — RLS scopes it to the account's memberships.
    /// Signed out → empty.
    func fetchAllLists() async throws -> [ListRow]

    /// Returns the joined list's id, or nil when the code matches no list. Other failures (network,
    /// signed out) throw.
    func joinListByCode(_ code: String) async throws -> String?

    /// Yields whenever the list or its items change server-side, AND on every (re)join of the underlying
    /// channel. Consumers respond to every element with a catch-up — realtime never carries data itself, it
    /// only says "worth asking". Missed-while-disconnected events are therefore a non-problem by construction.
    /// The channel is removed when iteration ends.
    func changes(listId: String) -> AsyncThrowingStream<Void, any Error>
}
