# F27 — SyncEngine catch-up (2026-11-13d)

## Summary
Extended the `SyncEngine` actor (`BabeGetThis/Core/Sync/Engine/SyncEngine.swift`) with a port of Android's
`catchUp`, `fullCatchUp`, `apply` and `shouldSkip` (SYNC-07, -08, -10, -11, -19):
- `catchUp(listId:)` runs under the engine's serial gate and is wrapped in `SafeCall`. With no session it does nothing.
  It fetches the list and its items since the stored sync point (gte; paging stays inside `SharedListRemote`), applies them,
  and only then moves the sync point to the newest `updated_at` it received.
- `fullCatchUp(listId:)` drops the sync point and then calls `catchUp`.
- `apply`:
  - Skips tombstones of rows this phone never had.
  - Claims ownerless replicas, even when the incoming data then loses to a dirty local row.
  - Uses `shouldSkip`: incoming data loses when the local row is dirty, when its stamp is no newer than the local one,
    or when it has no stamp.
  - Has an FK guard for items whose list isn't stored on this phone.
  - Always UPDATEs an existing list or item row, and INSERTs only a row that isn't there yet. It never uses REPLACE.
    Items go through `updateItem` as well; the project rule is stricter than Android's item upsert.

Tests: `BabeGetThisTests/Sync/Engine/SyncEngineCatchUpTests.swift` ports the 13 Android catch-up cases faithfully.
One case is slightly stronger than the Android version: the tombstone test also catches up the tombstoned list's own id,
because the fake answers `fetchList` only for the id it is asked about (the same as Android's fake).

## Acceptance
- [x] `./scripts/verify.sh bgt-night-3 -only-testing:BabeGetThisTests/SyncEngineCatchUpTests` (+ executed ≥ 13): done, `VERIFY PASS: 13 tests, 0 failures`
- [x] `./scripts/verify.sh bgt-night-3`: done, `VERIFY PASS: 650 tests, 0 failures`

Final line of the last verify run: `VERIFY PASS: 650 tests, 0 failures`

## Blocked
None.

## Follow-ups
- `catchUpAccount`, `claimDeviceLists`, `onAuthState` and `evictAccountLists` are not ported yet (outside F27), along with
  their SyncEngineTest cases (eviction, catch-up racing an eviction).
- Android's crash-reporter breadcrumbs (`sync: applied N lists, M items`) are not ported: the iOS engine has no reporter
  dependency yet.
