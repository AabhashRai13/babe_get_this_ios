# F36: Adoption notice dialog (2026-11-14b)

## Summary
`ListsView` now shows the one-time adoption notice (HOME-15) as an alert built on the existing
`ListsViewModel.adoptionNotice` state (fed live by `observeAdoptionNotice()` from the real ownership store);
no second data source. Copy lives in `AdoptionNoticeCopy` with Android's exact wording, singular for 1 list and
plural with the count otherwise. "OK" dismisses; "Privacy policy" dismisses and opens
`https://babegetthis.com/privacy-policy.html` via `openURL`. Dismissing clears the count in the store, so it does not return.

## Acceptance checklist
- `ListsViewModelTests/testAdoptionNoticeShownOnce` passes (executed 1 test): done
- Full `./scripts/verify.sh`: done
- Singular vs plural copy tests in `BabeGetThisTests/Lists/Adoption/`: done

Last verify line: `VERIFY PASS: 885 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- The dialog is a system alert; Android uses a Material AlertDialog with the same buttons. No visual check was done in the simulator (no UI test in scope).
