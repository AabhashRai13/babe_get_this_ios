# F34: Join dialog and Share live dialog (2026-11-14a)

## Summary
- **Join (SHARE-04):** the lists screen's top-bar "Join a shared list" button (Android `join_list_action`; it was a disabled "Join a list") now plays a light haptic and calls `ListsViewModel.startJoining()`. Signed out, it shows the existing `AuthPromptDialog` with the "Sign in to share" copy. Signed in, it shows the new `Features/Share/JoinListDialog`: title "Join a shared list", field "6-character code", placeholder "ABC234", caps keyboard, and the error shown under the field. The field model is the new `JoinListViewModel`, built fresh each time the dialog opens. It trims, uppercases and caps input at 6, like Android. "Join" works only at exactly 6 characters and never while `isJoining` is true. The join, its progress and its error still go through F13's `ListsViewModel.joinList`. On success the dialog closes and the list shows up through the existing live query.
- **Share live (SHARE-05, SHARE-06):** the placeholder sheet in `ListDetailPlaceholderView.swift` is now `Features/Share/ShareLiveSheet`. It builds a `ShareLiveViewModel` from `container.shareRepository` and `container.authState`. When the sheet appears it calls `ShareRepository.share(listId:)` and shows the code in large, letter-spaced type (`.largeTitle`, tracking 9, matching Android's displaySmall/4), the hint, "Copy" (to `UIPasteboard`) and "Done". A failure shows as the existing `Snackbar` for 4 seconds. Only the code and hint are shown, never who changed what. The view model sits behind a small `ListSharing` protocol, which `ShareRepository` conforms to.
- **Lost session:** if the session is lost between opening the sheet and the share, the sheet closes and the "Sign in to share" prompt appears through the new `ListDetailChromeModel.shareLiveNeedsSignIn()` hook.
- **Wiring (AppContainer):** a single cached `SupabaseClient` now serves both the auth repository (refactored to use it) and the shared-list remote. The frozen names `sharedListRemote: any SharedListRemote` (a `SupabaseSharedListRemote`), `syncEngine: SyncEngine` and `shareRepository: ShareRepository` are all built lazily on first use. `syncEngine` uses `PrefsSyncPointStore()`, the container's ownership store, and `liveSessionUserId`. The lists get a `DeferredListJoiner`, which looks up `shareRepository` on the main actor only when someone joins, so neither app launch nor test containers open a Supabase client. The two "F30 wires it" comments now say what is wired and what F30 still has to do.
- **Strings (STR-07):** Android's exact English wording, kept as SwiftUI literals in `ShareLiveCopy` / `JoinListCopy`.

## Acceptance
- [done] `verify.sh bgt-night-3 -only-testing:BabeGetThisTests/JoinListViewModelTests/testJoinEnabledOnlyAtSixChars` → `VERIFY PASS: 1 tests, 0 failures` (latest.json executed = 1)
- [done] `verify.sh bgt-night-3 -only-testing:BabeGetThisTests/ShareLiveViewModelTests` → `VERIFY PASS: 7 tests, 0 failures` (latest.json executed = 7; the 3 Android cases plus a lost session, copy, isSharing and copy wording)
- [done] `verify.sh bgt-night-3` → `VERIFY PASS: 836 tests, 0 failures`

Tests added: `ShareLiveViewModelTests` (7), `JoinListViewModelTests` (9: six chars, disabled while joining, trim, uppercase, cap, trim before cap, copy, `isJoining` during a real `ListsViewModel` join, reopen clears the error), and `ShareLiveChromeTests` (2).

Final line of the last full `./scripts/verify.sh bgt-night-3`: `VERIFY PASS: 836 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- `docs/PARITY.md` still marks SHARE-04/05/06 and STR-07 as `[todo]`. It is outside this task's owned paths.
- Android's analytics on share and copy (`ShareCodeCreated`, `ShareCodeShared`) are not ported (TEL-04).
- Share live is a medium-detent sheet, not an alert-style card, because the brief keeps the existing `.sheet(isPresented:)`. On failure the sheet stays open with the snackbar and a "Done" button.
- F30: sync triggers, the list repository's `catchUp`, a real `SyncKicking`, and realtime on `list-<id>`.
