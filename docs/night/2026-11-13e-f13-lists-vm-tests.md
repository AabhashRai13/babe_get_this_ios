# F13: ShoppingListViewModelTests (2026-11-13e)

## Summary
Ported the 36 non-telemetry cases of Android `ShoppingListViewModelTest` to `BabeGetThisTests/Lists/ShoppingListViewModelTests.swift`.
The view model was missing things the Android one has, so `ListsViewModel` gained them (all in `Features/Lists/`):
- `ListsDependencies.swift`: `ListsRepositoryProviding` (the repository slice the VM uses; `ShoppingListRepository` conforms), `ListJoining` (Android `ShareRepository.join`), and `autoNameVoiceList`.
- `ListsViewModel`: takes the protocol instead of the concrete repository (existing call sites unchanged), plus optional `shareJoiner` and `ownership`.
  New: `createListWithVoice`, join flow (`startJoining`, `joinList`, dialog/prompt/error/progress state), `isSessionExpired`, `adoptionNotice` / `dismissAdoptionNotice` / `observeAdoptionNotice`, `showSnackBar`.
- `undoDelete` now runs the restore in an unstructured `Task`, so cancelling the caller (Undo, then leave the screen) can't abort it. This is the iOS equivalent of Android's `applicationScope`; the test uses a fake that aborts on cancellation, so it fails without the change.

Android names map to iOS ones (`setSelectedTab` → `selectedTab`, create dialog → `isNamingList`, edit dialog → `renamingList`, `navigateToList` → `openListRequest`, error/undo events → `errorMessage`/`undoMessage`).
Existing `ListsViewModelTests.swift` was left untouched; no case was an exact duplicate.

## Acceptance checklist
- Targeted run (`-only-testing:BabeGetThisTests/ShoppingListViewModelTests`, executed >= 36): done (36 executed).
- Full suite: done.

Last `./scripts/verify.sh bgt-night-1`: `VERIFY PASS: 722 tests, 0 failures`

## Skipped cases
The 6 Android telemetry cases (voice-list ItemAdded/CategoryAutoAssigned, FirstItemAdded once, failed voice list reports nothing, join attempt reported, joiner marker, bad code reports reason): iOS v1 has no analytics/markers events. No lock, reminder or Got This cases exist in this test class.

## Blocked
Nothing.

## Follow-ups
- Updated after the PR #8 review: `ShareRepository` (F33, merged in the same branch) now conforms to `ListJoining`. `AppContainer` doesn't pass it yet, because it needs the `SyncEngine`, which F30 wires; the Join dialog is F34 and the toolbar's Join button stays disabled until then. Without a joiner, `joinList` sets `joinError` instead of returning silently.
- Updated after the PR #8 review: `ListsView` passes `createListWithVoice` (now in the voice sheet's `Persist` shape) to the voice sheet, observes the adoption notice, and `AppContainer` passes the real `PrefsListOwnershipStore`. The session-expired banner and the adoption dialog are still UI work for F24 and F36.
- Exactly 36 cases executed, so the threshold has no headroom.
