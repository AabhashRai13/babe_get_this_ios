# F11: Lists overview actions

## Summary
- Swipe-delete on list cards (shared `SwipeableCard`) with a 4 s Undo snackbar (shared `Snackbar`). The view model keeps the deleted list and its items and restores them through `restoreListWithItems`; no Undo is offered if the list was not captured (as Android).
- Long-press on a card (and a VoiceOver "Rename" action) opens the rename dialog.
- New `CreateListDialog` for create and rename: 40-character limit (over-long input is rejected whole, as Android), counter from 40/40, trimmed name, Save/Create disabled while blank. Its rules live in the pure `CreateListDialogState`, which is what the tests cover.
- The old `.alert` create dialog was replaced by this dialog.
- Strings from Android strings.xml: New List, Rename List, List name, Save, Create, Cancel, Undo, "%s deleted".

## Acceptance checklist
- testDeleteThenUndoRestoresList runs (1 executed, passes): done
- CreateListDialogTests (12 executed, needs 11): done
- Full suite: done

Last full `./scripts/verify.sh bgt-night-1`: `VERIFY PASS: 583 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- Locked-list PIN prompt before delete (Android `pendingLockedDelete`) is not ported; there is no lock or PIN feature here yet.
- Type/Voice chooser is F12; the FAB still opens the name dialog directly.
- The dialog is an overlay inside the lists screen, so the navigation bar is not dimmed behind it.
- Swipe, long-press and snackbar timing are not covered by UI tests; only the view model and dialog rules are.
