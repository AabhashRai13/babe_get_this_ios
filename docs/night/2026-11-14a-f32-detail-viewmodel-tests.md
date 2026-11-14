# F32: core ShoppingItemsViewModelTest cases (run 2026-11-14a)

## Summary
All 37 listed cases are in `BabeGetThisTests/ListDetail/ShoppingItemsViewModel/ShoppingItemsViewModelTests.swift`
(DET-14). Each one runs against the iOS type that owns the behaviour today: `ListDetailViewModel`,
`ListDetailChromeModel`, `ListLeaveGuard`, `CategoryPickerModel`, or the list repository for voice.
Behaviour stayed where it was. No case showed an iOS/Android difference, so `ListDetailViewModel.swift` is unchanged.
23 cases were already faithful ports elsewhere. I moved those (listed below) and wrote the other 14 new.

### Moved into ShoppingItemsViewModelTests
From `ListDetailViewModelTests`, unchanged:
- 232 `testDeleteItemCachesTheItemCallsRepositoryAndOffersUndoWithItemName`
- 247 `testUndoDeleteItemRestoresThePreviouslyDeletedItemViaRepository`
- 266 `testUndoDeleteItemWithNoPendingDeleteIsANoOp`
- 275 `testDeleteItemOnRepositoryErrorShowsTheErrorAndDoesNotCacheForUndo`
- 886 `testDeleteItemOffersNoUndoWhenTheItemWasNeverInState`
- 899 `testAFailedRestoreKeepsTheCacheSoUndoCanBeRetried`
- 715 `testAddItemSuccessClosesTheSheet`
- 728 `testAddItemFailureSurfacesTheErrorAndKeepsTheSheetOpen`
- 742 `testTogglePickedUpDelegatesToTheRepository`
- 829 `testTogglePickedUpFailureSurfacesTheError`
- 485 `testUiStateSplitsActiveFromCompleted`
- 497 `testUiStateIsEmptyForAnEmptyList`

From `LeaveEmpty/ListLeaveGuardTests`. The assertions are unchanged; only the setup helper is adapted (`loadedForLeaving`):
- 302 `testLeavingAnEmptyListWouldDeleteIt`
- 309 `testLeavingAListWithItemsKeepsIt`
- 318 `testLeavingAnEmptySharedListKeepsIt`
- 325 `testAddingTheFirstItemStopsTheQuestion`
- 337 `testNothingIsClaimedBeforeTheItemsHaveLoaded`
- 916 `testTeardownDeletesAListLeftEmpty`
- 932 `testTeardownWaitsForAnInFlightUndoBeforeDecidingTheListIsEmpty`
- 959 `testTeardownProceedsImmediatelyWhenNoUndoIsInFlight`

From `ItemEditTests` (in `ItemSwipeEditTests.swift`):
- 346 `testEditKeepsIdListIdCreatedAtAndPickedUp`: unchanged. It runs on an in-memory database.
- 431 `testEditFailureKeepsTheDialogOpenAndShowsTheError`: tightened to match Android. It now fails
  with `.database("write failed")` and asserts that exact message; before, it only asserted a non-nil message.
- 701 `testEditPrefillsTheDraftFromTheItem`: the edit sheet's state is built from the item being edited.

### New
- 391, 409: edit with an unknown id writes nothing. A successful edit returns true, which is what closes
  the edit sheet on iOS and clears the screen's `editingItem`.
- 458, 466: auth gate, through `ListDetailChromeModel.voiceFabTapped()`. Its `isAuthenticated` is private.
- 504, 520, 532: grouping into active sections, through `ListDetailViewModel.activeGroups`.
- 547, 555: SavedStateHandle intent. The list id comes from `ListDetailViewModel.listId` and the name from
  `ListDetailChromeModel.listName`. An empty id and name are kept as given.
- 675: Share as text, through `ListDetailChromeModel`, reading the view model's live items.
- 690: the iOS view keeps "add sheet showing" in its own SwiftUI `@State`, so no model owns it.
  The test covers what the models own: the sheet opens with a blank draft that can't be saved, and
  closing it without saving writes nothing.
- 844, 855: `CategoryPickerModel.resolveCategoryId()` with "Other". On success the new category is
  built locally from the name and selected. On failure, `ListDetailViewModel.add(_:picker:)` shows the
  error and skips the item.
- 871: no voice entry exists on the detail screen in this base (it is a TODO for F41). So this case
  runs against the real `ShoppingListRepository.addItemsToList(listId:drafts:)` on an in-memory database,
  which is what F41 calls. It checks that the result is `.success("L1")` and that the item is stored.

## Acceptance
- [done] `./scripts/verify.sh bgt-night-2 -only-testing:BabeGetThisTests/ShoppingItemsViewModelTests`
  passed: `VERIFY PASS: 37 tests, 0 failures`. The executed count is 37, which meets the at-least-37 check.
- [done] `./scripts/verify.sh bgt-night-2` passed: `VERIFY PASS: 832 tests, 0 failures`.

## Blocked
None.

## Follow-ups
- 690 and 701 test only what the models own, because the view's SwiftUI state (`showingAdd`,
  `editingItem` in `ListDetailPlaceholderView.swift`) decides which sheet is showing. To port Android's
  `showAddItemDialog` and `editingItem` exactly, that state would have to move into a model.
  This is a product and structure decision, outside this task.
- `ListDetailViewModelTests` still repeats the five list-completed cases that F18 put in
  `ListCompleted/ListCompletedEventTests`. One copy could be removed.
- Once F41 lands, 871 could also check the detail screen's voice save path end to end.
