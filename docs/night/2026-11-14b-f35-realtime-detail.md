# F35: realtime on the list detail screen (night 2026-11-14b)

## Summary
- New `Features/ListDetail/ListRealtimeLifecycle.swift` ports the realtime block of Android
  `ShoppingItemsViewModel.init`. It uses three small protocols: `ListShareStateSource`
  (adopted by `ShoppingListRepository`), `ListCatchingUp` (adopted by `SyncEngine`) and
  `ListChangesSource` (`SharedListRemoteChanges` wraps `SharedListRemote.changes(listId:)`).
  - RT-03 "Shared: catch up once, then subscribe." / "Unshared account list: catch up once, with no socket." /
    "Guest list: nothing." / "Torn down when the list is unshared or the screen closes."
  - RT-02 "Realtime carries no data: every signal → `catchUp(listId)`."
  - A share-state change replaces the previous follow, like Android's `collectLatest`, and repeated equal
    states are ignored (`distinctUntilChanged`).
  - The engine and remote are resolved lazily through closures, so a guest list (including every
    `-sampleData` list) never builds the Supabase client or sync engine.
- `ListDetailScreen` runs it in a `.task(id: list.id)`, so SwiftUI cancels it when the screen closes, and that
  closes the channel. The share-state keying happens inside `run()`, not in the task id: it is the
  `collectLatest` port, and the "shared while open" case can be unit tested that way. The `ListDetailScreen(...)`
  call and init are unchanged. Nothing in `App/` or `Features/Lists/` was touched, so the lists overview still never subscribes.
- RT-01: `SupabaseSharedListRemote.changes(listId:)` already uses a fresh `list-<listId>-<uuid>` topic for each
  subscription and calls `removeChannel` when the stream ends. No change was needed.
- Tests: `BabeGetThisTests/ListDetail/Realtime/RealtimeLifecycleTests.swift` has 7 cases. That is the 4 Android cases
  (lines 972, 986, 997, 1004) plus three more: closing the screen closes the channel, unsharing while open closes the
  channel, and an unrelated row change doesn't re-subscribe. All fakes, no network.

## Acceptance
- [done] `./scripts/verify.sh bgt-night-2 -only-testing:BabeGetThisTests/RealtimeLifecycleTests` + executed ≥ 4: `VERIFY PASS: 7 tests, 0 failures`
- [done] `./scripts/verify.sh bgt-night-2`: `VERIFY PASS: 888 tests, 0 failures`

## Blocked
None.

## Follow-ups
- PARITY.md RT-01/RT-02/RT-03 can be marked done (PARITY.md is outside this task's owned paths).
- F30 still has to wire `ShoppingListRepository`'s `catchUp` and the sync triggers. This task only adds the
  detail-screen realtime.
