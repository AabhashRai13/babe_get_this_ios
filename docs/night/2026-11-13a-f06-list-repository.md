# F06 night report: ShoppingListRepository (2026-11-13a)

## Summary
Ported Android `ShoppingListRepository` (create, voice create-with-items, rename, add items,
owner routing) and the `SyncKicker` seam to GRDB, in `BabeGetThis/Core/Repositories/ShoppingList/`:

- `SyncKicking.swift`: the `pushSoon()` protocol (the real SyncEngine is F26).
- `ShoppingList.swift`: domain model with `isCompleted`, and mappers from `ShoppingListWithItemCount` / `ShoppingListRecord`.
- `ShoppingListRepository.swift`: `allLists()` (re-queries when `AuthStateManager.dataOwner` changes),
  `isAccountList`, `listById`, `shareCode(listId:)`, `createList`, `createListWithItems` (one transaction),
  `addItemsToList`, `updateListName`. The owner is `dataOwnerId`. Lists with an owner are written `pendingSync`
  and kick `pushSoon()`. Names are trimmed, and a blank name returns `.validation("List name can't be empty.")`.
  A missing list returns `.notFound("That list no longer exists.")`. A draft category id is kept only if that
  category row exists. A list's first write is a plain INSERT, and renames are an UPDATE (never REPLACE).

Tests: `BabeGetThisTests/Repositories/ShoppingList/ShoppingListRepositoryTests.swift` (36 cases) plus test support
(`CountingSyncKicker`, `authStateFor`, `TestData.draft`, `firstValue`). It runs on an in-memory `AppDatabase`.

Ported cases: 31 from ShoppingListRepositoryTest, which is every case except delete/undo/deleteListIfEmpty (F07, F30)
and the 6 PIN lock cases (out of iOS v1). Also 5 from ShoppingListRepositorySharedTest: getShareCode, rename shared,
rename local-only, voice items to a shared list, and rename an unshared account list. Its reminder case is out of
iOS v1, and its delete/undo cases belong to F07.

## Acceptance
- [x] `./scripts/verify.sh bgt-night-2 -only-testing:BabeGetThisTests/ShoppingListRepositoryTests` + executed >= 36: done (`VERIFY PASS: 36 tests, 0 failures`, latest.json executed 36).
- [x] `./scripts/verify.sh bgt-night-2`: done.

Last full run: `VERIFY PASS: 393 tests, 0 failures`

## Blocked
None.

## Follow-ups
- Drafts use the existing `ItemDraft` (feature type, non-optional strings). Android's voice draft has nullable
  quantity, note and shop, so here an empty `note`/`shop` is stored as nil and an empty quantity is stored as "".
- No `ListOwnershipStore`, lock, delete, undo or reminder methods yet. F07 adds delete/undo, and lock/reminders are out of v1.
  F07 will need the repository to take a `SyncEngine` (for deleteListIfEmpty's catchUp) and possibly the ownership store.
- `allLists()` waits for the first non-loading auth state (`dataOwner` skips `.loading`), the same as Android's flatMapLatest over dataOwner.
