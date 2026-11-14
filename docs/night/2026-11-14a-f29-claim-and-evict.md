# F29 — claim and evict (night 2026-11-14a)

## Summary
- `SyncEngine` (BabeGetThis/Core/Sync/Engine/SyncEngine.swift) gains:
  - `claimDeviceLists(userId:) -> Result<Int, AppError>`, inside the serial gate:
    - drops other accounts' sync points;
    - on the first claim, records the ownerless shared ids as unverified;
    - runs the DAO's one-transaction `claimDeviceLists`, in the ACCT-03 step order;
    - runs `finishFirstRun`;
    - adds the claimed count to the adoption notice through `ListOwnershipStore`.
  - `onAuthState(_ state: AuthState) async -> Bool`, with the signature F30 needs:
    - authenticated → claim, returns true;
    - sessionExpired → claim, returns false;
    - unauthenticated → `finishFirstRun` under the gate, returns false;
    - loading → does nothing, returns false.
    - A lost session never evicts (ACCT-07).
  - `finishFirstRun()`: only marks the migration done. Android also remembers pre-update locks, but list lock is out of v1 (ACCT-04).
  - `evictAccountLists(andThen:)`, all in one gate step:
    1. best-effort `pushLocked` wrapped in its own `safeCall`, so a failed push doesn't stop the eviction;
    2. `deleteAccountLists` (`accountId NOT NULL OR shareCode NOT NULL`, items cascade, guest lists stay);
    3. `syncPoints.clear()`;
    4. `andThen`.
    - Nothing calls it yet; logout is F37.
- The existing `releaseUnverifiedClaims` (F28) is reused unchanged.
- `ShoppingListDao` needed no changes: `claimDeviceLists`, `otherAccountListIds`, `ownerlessSharedListIds` and `deleteAccountLists` were already there and match the Android DAO. `claimDeviceLists` is one GRDB write transaction, marks guest items pending before claiming the lists, and only UPDATEs/DELETEs.
- Nothing sends `picked_up_at`.
- Tests:
  - `SyncEngineClaimTests` has 14 tests:
    - the 10 Android cases;
    - the 2 cases moved unchanged from `SyncEngineAccountCatchUpTests` (removed there);
    - 2 end-to-end versions of those same two cases that go through `claimDeviceLists` exactly as Android's test does.
  - `SyncEngineEvictionTests` has 5 tests, the Android SyncEngineTest eviction cases at lines 485, 506, 533, 547 and 561.
  - `FakeSharedListRemote` gained an `onFetchAllLists` hook, the counterpart of Android's `fetchAllGate`, for the "eviction waits for a catch-up in flight" case.

## Acceptance
- [x] done: `./scripts/verify.sh bgt-night-1 -only-testing:BabeGetThisTests/SyncEngineClaimTests` → `VERIFY PASS: 14 tests, 0 failures` (needs at least 12)
- [x] done: `./scripts/verify.sh bgt-night-1 -only-testing:BabeGetThisTests/SyncEngineEvictionTests` → `VERIFY PASS: 5 tests, 0 failures` (needs at least 5)
- [ ] not done: `./scripts/verify.sh bgt-night-1` fails, but only on one test outside this task (see Blocked).

Last full verify, final line:
`VERIFY FAIL: rc=65 Executed 835 tests, with 2 failures (0 unexpected) in 11.105 (12.039) seconds`

## Blocked
- `CreateListDialogFieldTests.testTypingPastFortyStopsTheFieldAtForty` (BabeGetThisTests/Lists/) failed in all 3 full runs. The two failures above are its two assertions.
  - What happens: 38 × "a" + "XYZQ" is typed one key at a time with a 30 ms settle. The field ends at "…XYQ" (41 characters): Z is rejected, then Q gets in.
  - It hosts the SwiftUI `CreateListDialog` in a UIWindow and doesn't touch the sync engine, the DAO or anything this task changed. All 834 other tests pass.
  - Both the test and the dialog are outside my owned paths, so I couldn't investigate or fix it. Per the stuck rule I stopped after three runs.
  - It looks timing- or simulator-dependent (bgt-night-1). Worth re-running on a quiet machine and checking whether it also fails on the base commit 88e8576.

## Follow-ups
- F30: subscribe `onAuthState` to the auth state and kick a sync when it returns true. Wire `SyncEngine` in `AppContainer`.
- F37: logout calls `evictAccountLists(andThen:)` with the real sign-out as `andThen`.
- If list lock ever comes to iOS, `finishFirstRun` should record pre-update locks (`listDao.lockedListIds()` → `ownership.rememberLock`) like Android does, and the 2 list-lock claim cases (lines 308 and 318) can be ported.
