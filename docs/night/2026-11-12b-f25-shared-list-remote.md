# F25: SharedListRemote, Supabase implementation and keyset paging (night 2026-11-12b)

## Summary
Ported Android `SharedListRemote.kt`, `SupabaseSharedListRemote.kt` and `Paging.kt` into
`BabeGetThis/Core/Remote/SharedList/`:
- `SharedListRemote` protocol (Sendable, async throws): insertList, setShareCode, upsertLists, upsertItems,
  fetchList, fetchItems, fetchAccountItems, fetchAllLists, joinListByCode, changes(listId).
- `SupabaseSharedListRemote`:
  - The first push is a plain INSERT (`return=minimal`, no merge-duplicates). A `PostgrestError` with code
    `23505`, or a message containing "23505" or "duplicate key", returns false. Every other error, such as
    RLS 42501, is rethrown.
  - setShareCode is a targeted PATCH `{share_code}` with `id=eq.<id>` that returns the code the server
    holds, or nil when no row is visible.
  - The upserts merge duplicates.
  - The fetches use `gte` on updated_at when a since is given.
  - joinListByCode calls the RPC `join_list_by_code(p_code)` and returns nil on `invalid_code`.
  - changes() opens one channel `list-<id>` with postgres changes on `lists` (`id=eq`) and `items`
    (`list_id=eq`), plus every SUBSCRIBED status, merged into an `AsyncThrowingStream<Void>`. The channel is
    removed when iteration ends.
- `SharedListPaging`:
  - Page size 1000.
  - Keyset paging on `(updated_at, id)` ascending. The next page is
    `updated_at > s OR (updated_at = s AND id > last)`, sent as a PostgREST `or` filter with the values
    double-quoted.
  - Paging stops at the first short page.
  - supabase-swift percent-encodes `+` in query values (checked in a test), so timezone offsets survive.
- Encoded items never contain `picked_up_at` (reuses `ItemRow`; asserted on the upsert body).

Tests (no network; SupabaseClient on `http://127.0.0.1:54321` with a dummy key, an in-memory auth storage
and a `SharedListURLStub` URLProtocol session):
- `PagingTests` (6): short-page stop and cursors, the extra empty request after a full page, an empty
  first page, the page size, the `or` filter text, and an end-to-end two-page fetchAllLists over the stub.
- `SharedListRemoteTests` (18): plain INSERT shape, duplicate insert → false (by code and by message),
  42501 rethrown, setShareCode shape / nil, upsert shapes, no `picked_up_at` sent, fetch filters (id,
  list_id, gte since, none for account/discovery), RPC success / invalid_code → nil / other errors thrown.

## Acceptance
- [done] `./scripts/verify.sh bgt-night-3 -only-testing:BabeGetThisTests/PagingTests/testKeysetPagingStopsAtTheFirstShortPage` → `VERIFY PASS: 1 tests, 0 failures`
- [done] `./scripts/verify.sh bgt-night-3 -only-testing:BabeGetThisTests/SharedListRemoteTests/testDuplicateInsertReturnsFalse` → `VERIFY PASS: 1 tests, 0 failures`
- [done] `./scripts/verify.sh bgt-night-3` → `VERIFY PASS: 206 tests, 0 failures`

Last full verify run: `VERIFY PASS: 206 tests, 0 failures`

## Blocked
None.

## Notes
- Bash calls such as `ls` and `grep` on the shared SPM checkout (`ios-night/_state/spm`) were denied. I read
  the supabase-swift sources with the Read tool instead.
- Ordering is sent as `updated_at.asc.nullslast,id.asc.nullslast`, because supabase-swift always adds a
  nulls clause. This is equivalent to Android's `updated_at.asc`, since `updated_at` is NOT NULL.

## Follow-ups
- No unit test covers `changes(listId:)`, because it needs a realtime socket. Cover it in the Docker
  integration target (SRV-06 / RT-01).
- `SafeCall` does not map `PostgrestError` / `HTTPError` yet, so they become `.unknown`. Do this when
  ShareRepository and SyncEngine are ported.
- An in-memory `FakeSharedListRemote` for the SyncEngine / ShareRepository test ports (SYNC-16/19,
  SHARE-03).
