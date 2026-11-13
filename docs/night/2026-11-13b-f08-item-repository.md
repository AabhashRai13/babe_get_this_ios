# F08: ShoppingItemRepository (2026-11-13b)

## Summary
Ported Android `ShoppingItemRepository` (DATA-07) to `BabeGetThis/Core/Repositories/ShoppingItem/`:
`itemsByListId` (stream, category names resolved, re-emits on item or category change), `addItem`
(trimmed, blank name is a validation error), `updateItem`, `togglePickedUp` (missing item is a quiet no-op),
`deleteItem` (tombstone on account lists, hard delete on guest lists), `restoreItem` (upsert revives a tombstone).
Account-list writes set `pendingSync` and call `SyncKicking.pushSoon()`; guest-list writes stay clean and quiet.
Added `StoredShoppingItem` (repository-level model with listId and timestamps; the existing view-layer
`ShoppingItem` has neither). Got This (`TickStore`, `pickedUpAt`, `TickResult`) and reminders are left out;
iOS never writes `picked_up_at`.

Tests: `ShoppingItemRepositoryTests`, 15 cases ported from `ShoppingItemRepositorySharedTest`. Left out: the
tick-time, TickResult/purchase-record and reminder cases. Added: blank-name validation, name trimming,
untick, edit-keeps-ticked, category name resolution.

## Acceptance
- [x] `verify.sh` with `-only-testing:BabeGetThisTests/ShoppingItemRepositoryTests`: executed 15 (>= 11), done
- [x] Full `verify.sh`: done

Last verify line: `VERIFY PASS: 474 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- `togglePickedUp` returns `Result<Void, AppError>`; if Got This lands later it should return a tick result like Android.
- `updateItem` writes `deletedAt = nil` (same as Android's domain-to-entity copy); callers shouldn't update tombstoned items.
