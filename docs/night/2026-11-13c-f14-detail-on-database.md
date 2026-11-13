# F14: List detail on the database (night 2026-11-13c)

Branch `night/2026-11-13c/f14-detail-on-database`, simulator `bgt-night-2`. Parity IDs: DET-02, DET-16, STR-05.

## Summary
- `ListDetailViewModel` now follows the list's items live through `ShoppingItemRepository.itemsByListId`. It is a port of Android `ShoppingItemsViewModel` without the lock, share, reminder, Got This and telemetry parts.
  - Tick/untick, delete, undo and add all go through the repository. iOS still never writes `picked_up_at`, because the repository has no such field.
  - Failures come back from `safeCall` as `AppError` and show their `message` as a snackbar.
  - Like Android, the undo cache is cleared only after a successful restore. Undo is offered only when the deleted item was on screen. The undo `Task` isn't tied to the screen, so it still runs if the user leaves.
  - The add sheet stays open when a save fails (Android behaviour), so its callback is now async and returns whether the item was saved.
- The derived state (sorting, active/completed split, shop → category groups) moved into a value type, `ListDetailContent`. It is built once per database emission, like Android's `ShoppingItemsUiState`.
- The repository is reached through a small protocol, `ListDetailItemsSource`, so tests can make writes fail. `ShoppingItemRepository` conforms to it unchanged.
- **List completed:** the view model detects the not-finished → finished change, including deleting the last unticked item. On that change it plays `Haptic.success` and increments `completionCount`. Opening a list that is already finished does nothing.
- **Progress card celebration (DET-16):** `ProgressCardCelebration` is the testable form of Android's `hasInitialized` guard. On the change to finished, `ProgressCardView`:
  - snaps the card to 0.85 and springs it back (damping ratio 0.75);
  - pops the check in with a bouncy spring (damping ratio 0.2, StiffnessMediumLow);
  - pulses the container toward primary (180 ms) and back (320 ms).
- **Wiring:**
  - `AppContainer` exposes `itemRepository`. `ListDetailPlaceholderView(list:)` is still the entry point; it reads the container from the environment, so `Features/Lists` is unchanged.
  - `SampleListSeeder` seeds Sunday Roast with the fixed `ShoppingItem.sundayRoast` items, so `-sampleData -openList sample-sunday-roast` still shows them. The other sample lists keep their placeholder items.
- `ShoppingItem` now stores `categoryName` taken from the repository, so custom categories show their name. Without one, it falls back to `DefaultCategories`.
- **STR-05:** the detail strings in use already match Android `strings.xml`: "ACTIVE ITEMS", "COMPLETED", "N Item(s)", "List created!", "Add your first item to get started", "Add first item" and "%s deleted". The leave-empty-list strings belong to DET-12 (see Follow-ups).

## Tests
- `ListDetailViewModelTests` has 25 cases.
  - Ported from Android `ShoppingItemsViewModelTest`, against `FakeListDetailItemsSource`:
    - the 5 ListJustCompleted cases (they also check the Success haptic);
    - 6 delete/undo cases;
    - add success and add failure;
    - toggle delegation and toggle failure;
    - the 2 uiState cases.
  - Database-backed cases, using the real repository on an in-memory GRDB: the required `testItemsAreObservedLiveFromTheDatabase`, the sample-list case, add validation, delete-then-undo, and the empty-list prompt.
  - 3 cases kept from the earlier in-memory tests: dismissing undo makes the delete final, the undo snackbar copy and duration, and nothing shows before the first load.
- `ListDetailContentTests` has 10 cases: the grouping and ordering cases from the earlier tests, an active-sections case and a stored-category-name case.
- `ProgressCardTests` has 2 cases, including the required `testCelebrationPlaysOnlyOnTransitionToFinished`.

## Acceptance
- [done] `./scripts/verify.sh bgt-night-2 -only-testing:BabeGetThisTests/ListDetailViewModelTests/testItemsAreObservedLiveFromTheDatabase` → `VERIFY PASS: 1 tests, 0 failures`
- [done] `./scripts/verify.sh bgt-night-2 -only-testing:BabeGetThisTests/ProgressCardTests/testCelebrationPlaysOnlyOnTransitionToFinished` → `VERIFY PASS: 1 tests, 0 failures`
- [done] `./scripts/verify.sh bgt-night-2` → last line: `VERIFY PASS: 584 tests, 0 failures`

## Blocked
- Nothing.
- One command was denied: a `git -C <android> grep` whose pattern contained backticks. I read the same file with `git show` instead.

## Follow-ups
- **DET-12 (leave an empty list):** the "Delete this empty list?" dialog and the delete-if-empty teardown need `ShoppingListRepository.deleteListIfEmpty` (DATA-06), which doesn't exist yet. That is also why the list repository isn't used by the detail screen yet.
- **Sunday Roast counts:** the overview card now shows Sunday Roast as 1/5, from the database, while `ShoppingListSummary.samples` still declares 3/7. The overview screenshot changes slightly. Aligning the sample summary is a `Features/Lists` change, which this task doesn't own.
- **Not ported:** RT-03 (realtime/catch-up while the screen is open), DET-06 (edit), DET-10 (voice FAB) and SHARE-05 (share live) still need their ShoppingItemsViewModelTest cases ported.
- **Add-item sheet:** the category picker still lists only the default categories (DET-08). A custom category on an existing item does show its name.
- **Not checked in the simulator:** the celebration animation and the Success haptic were only exercised through their logic tests. Nobody looked at them in the simulator or a screenshot.
