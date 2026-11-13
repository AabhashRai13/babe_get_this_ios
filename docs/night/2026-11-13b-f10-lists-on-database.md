# F10 — Lists overview on the database (2026-11-13b)

## Summary
- `ListsViewModel` now follows `ShoppingListRepository.allLists()` (GRDB observation, current data owner,
  `createdAt DESC`, live updates) through `observeLists()`, run from the screen's `.task`. Create goes through
  `repository.createList(name:)`; failures surface as an alert (`errorMessage`). `init(lists:)` remains as a
  fixed snapshot for previews and pure tests.
- `AppContainer` builds the on-disk `AppDatabase` and the `ShoppingListRepository` (with a `NoOpSyncKicker`
  until the sync engine lands). `-sampleData` and `AppContainer.preview` use an in-memory database seeded by
  `SampleListSeeder` and a signed-out in-memory `AuthStateManager` (no Keychain access).
- `DateGrouping.swift`: `TimePeriod.of(_:now:calendar:)` + `displayName`, ported from `DateGrouping.kt`;
  13 tests ported from `DateGroupingTest.kt`.
- Screen: tab pills (outlined/filled SF Symbols, primary-filled selected pill, 200 ms colour animation,
  Medium haptic), per-tab panes that slide in the direction of travel (280 ms, with fade), greeting card on
  the Active tab only (as first row, with the signed-in user's first name), date-bucket headers (6 pt primary
  dot + bold label), FAB only on Active, per-tab empty text.
- List card (`ListCardContent`): check + muted name on Completed, "No items yet" when empty, "Y items" on
  Completed, "X/Y items" on Active.

## Acceptance
- [x] DateGroupingTests ≥ 13 — `VERIFY PASS: 13 tests, 0 failures`
- [x] ListsViewModelTests/testGreetingShowsOnActiveTabOnly — `VERIFY PASS: 1 tests, 0 failures`
- [x] ListsViewModelTests/testCompletedCardShowsCheckAndItemCount — passed (run together with the next one: `VERIFY PASS: 2 tests, 0 failures`)
- [x] ListsViewModelTests/testEmptyListSubtitleIsNoItemsYet — passed (same run)
- [x] Full suite — `VERIFY PASS: 483 tests, 0 failures`

Last full `./scripts/verify.sh bgt-night-3`: `VERIFY PASS: 483 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- Android navigates into a newly created list (`navigateToList`); iOS still only switches to Active. Belongs
  with the create-list chooser (F12) or navigation work.
- `AppDatabase.onDisk()` failure is a `fatalError` at launch, like invalid config. Worth revisiting with crash
  reporting.
- Session-expired banner, account avatar/sign-in pill and adoption notice from `ShoppingListScreen.kt` are
  not part of F10's parity IDs and remain to do.
- `ListDetailPlaceholderView` still uses its own in-memory items; sample lists seed placeholder items
  ("Item 1"…) in the database only to drive the overview counts.
- No UI/screenshot check was run for the new tab motion; worth a visual pass in the screenshot task.
