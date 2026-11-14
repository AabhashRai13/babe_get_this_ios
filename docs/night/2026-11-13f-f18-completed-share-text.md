# F18: list-completed event and share as text (2026-11-13f)

## Summary
- The list-completed transition logic and Success haptic were already in `ListDetailViewModel` (`completionCount`, `apply`). F18 adds the 5 ListJustCompleted cases as `ListCompletedEventTests`.
- New `ShoppingListShareText` formatter, ported exactly from Android, with `ShoppingListShareTextTests` (9 cases).
- "Share as text" now shares the formatted list: `ListDetailScreen.init` passes a `shareTextProvider` to `ListDetailChromeModel` (a few lines in `ListDetailPlaceholderView.swift`). The existing `ActivityShareSheet` presents it.

## Acceptance checklist
- ShoppingListShareTextTests, at least 9 executed: done (9 tests, 0 failures)
- ListCompletedEventTests, at least 5 executed: done (5 tests, 0 failures)
- Full suite: done

Last `./scripts/verify.sh bgt-night-1`: `VERIFY PASS: 771 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- The 5 completion cases are now duplicated in `ListDetailViewModelTests`; one set could be dropped later.
- The share action itself isn't covered by a UI test; only the formatter is.
