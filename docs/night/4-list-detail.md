# Task 4: List detail screen

## Summary
`ListDetailPlaceholderView` (same type and `init(list:)`) is now the real list detail screen, so `ListsView` is unchanged.
It is built from `ListDetailViewModel` (`@MainActor @Observable`, in-memory), `ShoppingItem`, `ItemDraft`,
`ListDetailComponents.swift` (progress card, section and group headers, item card, chips, undo snackbar) and `AddItemSheet`.
Only `AppColors` and `AppMetrics` are used, with no hex values. Android's long-press edit mode and the share, lock and
voice actions are out of scope.

## Acceptance checklist
- Replaces `ListDetailPlaceholderView` with the same type name and init: done
- Progress card (count, percentage, bar); ACTIVE ITEMS grouped by shop then category; COMPLETED below: done
- Item card with tick circle, name, italic note, quantity and category chips: done
- Tick/untick moves items between sections; swipe to delete with an Undo snackbar (auto-dismiss after 5 s): done
- Add-item sheet with name and quantity required, category picker, shop and note: done
- In-memory `@Observable` view model with 10 unit tests (grouping, progress, tick, delete/undo, add validation): done
- `AppColors` / `AppMetrics` only: done
- Fixed sample data for `sample-sunday-roast`; other lists start empty: done
- Light and dark screenshots in `docs/night/screens/`: done (reviewed; layout adjusted once)
- `./scripts/verify.sh bgt-night-4` passes: done

## Verify result
`VERIFY PASS: 30 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- The sample screenshots show only the top of the list, because the Completed card is below the fold. The brief does not allow scrolling.
- The category list is hard-coded; Android's category data and "create new category" arrive with the data layer.
- Progress-card celebration animation, haptics, item editing and the share, lock and voice actions are not ported.
- The add-item sheet and the swipe-delete / undo UI flow have no UI tests, only view-model tests.
