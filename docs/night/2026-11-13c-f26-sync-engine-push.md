# F26: SyncEngine push (2026-11-13c)

## Summary
- `BabeGetThis/Core/Sync/Engine/SyncEngine.swift`: a `SyncEngine` actor ported from Android `SyncEngine.kt`
  (push part only).
  - Serial gate (SYNC-02): a FIFO async lock inside the actor (`serially`), because an actor alone is reentrant
    at every `await`. This is Android's `Mutex`. `push()` takes it; `pushLocked()` runs inside it.
  - `push()` (SYNC-04): drops never-sent tombstones (no session needed), returns if signed out, INSERTs each
    `onServer = false` list one by one (an "already exists" answer moves it into the upsert batch), marks it
    onServer, upserts the rest in one batch, clears list flags with the guarded `markListSynced`, then upserts
    pending account items and clears their flags with `markItemSynced` (SYNC-06). Lists always go before items.
    Returns `Result<Void, AppError>` through `SafeCall`. Item rows use `LocalItemRecord.toRow()`, which never
    sends `picked_up_at`.
  - `hasUnsyncedChanges(accountId:)` (SYNC-13): pending account lists + pending account items > 0.
  - The constructor already takes `SyncPointStore` and `ListOwnershipStore`, so F27–F29 can extend the actor
    without changing its stored properties.
- `SyncRecordConversions.swift`: `ShoppingListRecord`/`ShoppingItemRecord` ↔ `LocalListRecord`/`LocalItemRecord`
  (`syncLocal`, both directions; F27's apply needs the reverse).
- Tests (`BabeGetThisTests/Sync/Engine/`): `SyncEnginePushTests` ports the 14 push/outbox cases and the 3
  non-Got-This unsynced cases of `SyncEngineTest` (SYNC-16), against an in-memory GRDB database.
  `SyncEngineFakes.swift` ports `FakeSharedListRemote`, `FakeSyncPointStore` and `FakeListOwnershipStore` from
  Android `testing/SyncFakes.kt` for the later engine tasks to reuse.

## Acceptance
- [done] `./scripts/verify.sh bgt-night-4 -only-testing:BabeGetThisTests/SyncEnginePushTests` + executed ≥ 17:
  `VERIFY PASS: 17 tests, 0 failures`
- [done] `./scripts/verify.sh bgt-night-4`: `VERIFY PASS: 582 tests, 0 failures`

Last verify run (full suite): `VERIFY PASS: 582 tests, 0 failures`

## Blocked
None.

## Follow-ups
- Android logs sync breadcrumbs (`crashReporter.breadcrumb("sync: pushed N lists, M items")`). iOS has no
  crash-reporter breadcrumb API yet, so they are left out. Add them when Crashlytics is wired in.
- The Got This hooks (`gotThis.dropNeverSentLists`, `gotThis.push`, `unsyncedCount`) are left out because
  Got This is out of iOS v1 (GOT-06). `dropNeverSentLists` is replaced by `listDao.deleteNeverSentDeletedLists()`.
- `hasUnsyncedChanges` is `async throws -> Bool` (Android: a plain suspend Boolean, outside the lock). Its
  future caller (profile sign-out warning) has to handle the throw.
- The fake's `fetchAllLists` has no entry/gate hooks yet (Android `fetchAllEntered`/`fetchAllGate`). F29's
  eviction-vs-catch-up race test will need them.
- Wiring the engine into `AppContainer` (and making it the `SyncKicking` implementation) is F30's trigger work.
