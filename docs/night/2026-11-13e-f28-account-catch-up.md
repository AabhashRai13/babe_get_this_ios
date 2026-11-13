# F28: SyncEngine catchUpAccount (run 2026-11-13e)

## Summary
- Ported Android `SyncEngine.catchUpAccount()` (SYNC-09) into the `SyncEngine` actor, behind the existing serial gate:
  1. Read the known account list ids.
  2. Run `fetchAllLists()` discovery with no since filter.
  3. Apply the non-fresh rows.
  4. Release unverified first-run claims, but only when discovery returned rows.
  5. If any list is known, run one account-wide `fetchAccountItems(since: syncPoints["account"])` and apply it.
  6. Move the account sync point to the newest stamp over those items and the discovered lists.
  7. Fully pull each fresh list.
- Also added `SyncEngine.accountSyncPoint = "account"` and a private `releaseUnverifiedClaims`.
- Every apply goes through the existing single-transaction `apply` (dirty local rows win, UPDATE never REPLACE, FK guard), so the race fixes are unchanged. A fresh list and its full history land in one apply, so one transaction. Nothing sends `picked_up_at`.
- `FakeSharedListRemote` gained these, ported from Android `SyncFakes.kt`: `itemReads`, `accountItemSinces`, `failAccountItems` and `failItemFetchFor`.
- New `SyncEngineAccountCatchUpTests` with 14 cases (SYNC-17).

Skipped Android cases (as the brief says):
- Got This: `purchases are fetched only once the items have landed`
- Got This: `a failed clear followed by a catch-up does not bring back a cleared purchase`
- Got This: `a failing Got This pull does not fail the account catch-up`
- List lock: `a list that comes back after sign-out keeps its lock`

SRV-05 (the `items(updated_at)` index) is server-side. The engine relies on it through `fetchAccountItems`, and no client code is needed.

## Acceptance
- [done] `./scripts/verify.sh bgt-night-3 -only-testing:BabeGetThisTests/SyncEngineAccountCatchUpTests`, executed ≥ 14: `VERIFY PASS: 14 tests, 0 failures`
- [done] `./scripts/verify.sh bgt-night-3`: `VERIFY PASS: 700 tests, 0 failures`

Last verify line: `VERIFY PASS: 700 tests, 0 failures`

## Blocked
None.

## Follow-ups
- Nothing calls `catchUpAccount()` yet (the app-open/SyncTrigger kick); wire it when SyncTrigger is ported.
- The skipped list-lock case depends on `ListRow.toRecord` honouring `lockedIds` for new rows. Port it with the lock feature.
- Android also leaves crash-reporter breadcrumbs here. The iOS engine has no crash reporter yet.
