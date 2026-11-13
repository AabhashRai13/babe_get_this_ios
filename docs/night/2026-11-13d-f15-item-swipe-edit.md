# F15 item swipe / edit: night 2026-11-13d

## Summary
- Item rows are now wrapped in the shared `SwipeableCard`: swipe right toggles picked up, swipe left deletes (with the existing undo snackbar). This replaces the List `.swipeActions` delete.
- Tapping a card opens the add/edit dialog (`AddItemSheet(editing:)`), titled "Edit Item" with a "Save" button, pre-filled from the item. The tick circle still toggles.
- `ListDetailViewModel.edit(_:with:)` goes through `ShoppingItemRepository.updateItem` and keeps id, listId, createdAt and isPickedUp; shop and note are trimmed and blank becomes nil. A failure shows the error and keeps the dialog open.
- `ItemDraft` has `nameCounter`, `noteCounter` and `shopCounter`: `n/limit` shows once a field reaches its limit (60, 80, 40), like Android's `supportingText`.
- `ItemCardActions` ties the card's toggle, edit and delete to a `SwipeableCardController`, so the swipe wiring is testable.

## Acceptance checklist
- ItemEditTests/testEditKeepsIdListIdCreatedAtAndPickedUp: done (VERIFY PASS: 1 tests, 0 failures)
- ItemCardTests/testSwipeRightTogglesPickedUp: done (VERIFY PASS: 1 tests, 0 failures)
- ItemDraftTests/testCounterShowsAtTheLimit: done (VERIFY PASS: 1 tests, 0 failures)
- Full suite `./scripts/verify.sh`: done. Last full run: `VERIFY PASS: 647 tests, 0 failures`.

I did not run the `python3 -c ... latest.json` half of the acceptance commands (not on the allowed list); the orchestrator re-runs them.

## Blocked
Nothing.

## Follow-ups
- The Android `AddItemDialog` category search/dropdown and "Other" create-new-category flow are not ported (the iOS sheet uses a plain Picker, as before). An item whose category is a custom one has no matching Picker tag in edit mode, so it shows as unselected.
- No UI test for tap-to-edit or the on-screen counters (unit tests cover the logic only).
- The Android dialog tests for button placement and the keyboard are Compose-specific and have no iOS equivalent.
