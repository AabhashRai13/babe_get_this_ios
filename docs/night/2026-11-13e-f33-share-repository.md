# F33: ShareRepository (run 2026-11-13e)

## Summary
- `BabeGetThis/Core/Sync/Share/ShareRepository.swift`: port of Android `ShareRepository.kt`.
  - `share(listId:)` (SHARE-01) follows Android step by step. A missing list gives NotFound. An existing code is returned as is. With no session it gives Auth. A list not yet on the server is pushed first, and if it is still not there the call gives Network("Couldn't share — check your connection."). The code is set on the server first and stored locally second, and the local store keeps the code the server returns (`setShareCode` is a targeted UPDATE).
  - Codes (SHARE-02) are 6 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. The random source is an injectable `RandomIndex` closure, and the default is `Int.random`. A unique-constraint clash fails the call, and a retry generates a fresh code.
  - `join(code:)` (SHARE-03) trims the code and calls `joinListByCode`. If that returns nil the call gives NotFound("That code didn't match any list."). Otherwise it runs `fullCatchUp(listId:)`, and a failed pull comes back as an error.
  - Small protocols: `ShareListStore`, which `ShoppingListDao` conforms to with its existing `listRaw` and `setShareCode`, and `ShareSyncing`, which `SyncEngine` conforms to with its existing `push` and `fullCatchUp`. No engine methods were missing, and no files outside the owned paths were edited.
  - It follows the iOS repository convention `async throws -> Result<_, AppError>`; only CancellationError is thrown.
- Tests in `BabeGetThisTests/Sync/Share/`:
  - `ShareRepositoryTests` has 15 tests: all 13 Android `ShareRepositoryTest` cases ported faithfully, plus 2 SHARE-02 cases (the code comes from the injected random source; a clash fails and the retry uses a new code).
  - `ShareRepositoryFakes.swift` holds `ShareTestRemote` and `ShareTestRandom`. `ShareTestRemote` wraps the shared `FakeSharedListRemote` and adds Android's `shareCodeRequests`, `serverShareCode` and `shareCodeRowMissing` knobs, plus a clash counter. `ShareTestRandom` is a seeded LCG. The tests use a real in-memory database and the real SyncEngine.
- SRV-02 (write-once share_code) is covered on the client side by adopting whatever code the server returns ("when another phone shared first, its code wins").

## Acceptance
- [done] `./scripts/verify.sh bgt-night-4 -only-testing:BabeGetThisTests/ShareRepositoryTests` with executed ≥ 13: `VERIFY PASS: 15 tests, 0 failures` (latest.json executed = 15).
- [done] `./scripts/verify.sh bgt-night-4`: `VERIFY PASS: 701 tests, 0 failures`.

Last verify.sh final line: `VERIFY PASS: 701 tests, 0 failures`

## Blocked
None.

## Follow-ups
- Move the share-code knobs (`shareCodeRequests`, `serverShareCode`, `shareCodeRowMissing`) into the shared `FakeSharedListRemote` in `BabeGetThisTests/Sync/Engine/SyncEngineFakes.swift`, then drop the `ShareTestRemote` wrapper. That file is outside this task's owned paths.
- Wire `ShareRepository` into `AppContainer`, using `db.lists`, the `SupabaseSharedListRemote`, the `SyncEngine` and the session's user id. That is also outside the owned paths and is needed by SHARE-04/05.
- With the default SafeCall mapping, a unique-constraint clash (409) shows as `.auth("Request failed.")`. This matches Android's default mapping, but a share-specific `onClientError` copy may read better.
