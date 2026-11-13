# F07: List delete, undo restore and never-sent tombstone cleanup

## Summary
Added `deleteListAndCaptureItems(listId:)` and `restoreListWithItems(list:items:)` to `ShoppingListRepository`,
ported from Android. Account lists soft-delete (tombstone + `pushSoon`); guest lists hard-delete with CASCADE.
Undo of a tombstoned account list is an UPDATE that clears `deletedAt` (never insert-or-replace), keeping
`accountId` and `shareCode`. If the row is gone (guest list, or a never-sent list the push dropped), undo
re-inserts list + items in one transaction under the current data owner. `ListDeleteUndoTests` has 9 cases:
5 from `ShoppingListRepositoryTest` and 4 from `ShoppingListRepositorySharedTest`.

## Acceptance
- [x] `ListDeleteUndoTests` run with at least 9 executed: done (9 tests)
- [x] Full `./scripts/verify.sh` suite: done

Last verify line: `VERIFY PASS: 468 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- `deleteListIfEmpty` and its Android tests (shared-list guard, server catch-up before tombstoning, lost session)
  are not ported: the iOS repository has no SyncEngine dependency yet and the brief did not list them.
- The tombstone cleanup itself is the existing DAO `deleteNeverSentDeletedLists()`, exercised by the restore-after-drop test.
