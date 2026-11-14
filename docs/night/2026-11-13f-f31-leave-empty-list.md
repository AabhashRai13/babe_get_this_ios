# F31: Leave-empty-list confirmation and deleteListIfEmpty (2026-11-13f)

## Summary
- `ShoppingListRepository.deleteListIfEmpty(listId:)` ported from Android (DATA-06): missing → false;
  shared → never deleted; guest → atomic hard delete via the DAO; unshared account list not yet on
  the server → atomic tombstone + push kick; account list on the server → only with a live session
  and a successful catch-up, then atomic tombstone + push kick.
- The catch-up is injected as an optional `catchUp` closure (default nil) so `AppContainer` (not owned)
  compiles unchanged. With no engine wired, a list already on the server is kept (the safe side).
- DET-12: new `ListLeaveGuard` (Features/ListDetail/ListLeaveGuard.swift) + `LeaveEmptyListModifier`.
  While the list is loaded, empty and unshared, the back button is replaced and asks
  "Delete this empty list?" / "This list has no items, so it will be deleted when you leave." with
  "Delete list" (destructive) and "Keep editing". On disappear the guard runs delete-if-empty after any
  in-flight undo (tracked via `trackUndo`) finishes.
- Shared-file edits in `ListDetailPlaceholderView.swift` kept to a few lines (one init param, one
  `@State`, the undo call, one modifier line). `ListDetailViewModel.swift` untouched.
- Tests: `DeleteListIfEmptyTests` (15 = 2 DeleteListIfEmptyTest + 10 ShoppingListRepositoryTest +
  3 ShoppingListRepositorySharedTest; real in-memory DB, real SyncEngine over the fake remote) and
  `ListLeaveGuardTests` (11: the Android VM `leavingDeletesList` / `onCleared` cases plus dialog flow).

## Acceptance
- `verify.sh bgt-night-2 -only-testing:BabeGetThisTests/DeleteListIfEmptyTests` with executed ≥ 15: **done**
  (`VERIFY PASS: 15 tests, 0 failures`)
- `verify.sh bgt-night-2`: **done**

Last full run: `VERIFY PASS: 783 tests, 0 failures`

## Blocked
- None.

## Follow-ups
- Wire a real `SyncEngine` into `AppContainer` and pass `catchUp: { try await engine.catchUp(listId: $0) }`
  to `ShoppingListRepository`; until then, empty account lists already on the server are never auto-deleted.
- The custom back button replaces the system one only while leaving would delete the list, which also
  disables the interactive swipe-back in that state (same as Android's BackHandler intercepting back).
