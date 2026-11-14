# F37: Profile sheet (run 2026-11-14e)

## Summary
The real profile sheet replaces the F24 placeholder. It is a port of Android `ProfileBottomSheet` / `ProfileViewModel`.
- `Features/Profile/ProfileViewModel.swift`: name editing (`onNameChanged`, `hasNameChanged`, `saveName`) with "Name cannot be empty" / "Name updated". Log out: push, then the unsynced check on the data owner, then the "Sign out?" warning or the eviction with the sign-out inside it, then a Welcome reset. Delete account: push, then `deleteAccount`, then the eviction, then a Welcome reset, then "Your account has been deleted". A failed deletion never evicts. Name and email are observed, not snapshotted, so switching accounts refreshes them.
- `Features/Profile/ProfileDependencies.swift`: small protocols (`ProfileAccountSource`, `ProfileAuthenticating`, `ProfileSyncing`, `ProfileWelcomeResetting`). Each has an adapter over the existing code: `AuthStateManager` (through Observation tracking), `SupabaseAuthRepository`, `WelcomeRepository` and `SyncEngine`. Sync and auth are resolved lazily (`DeferredProfileSync` / `DeferredProfileAuth`), so building the container still opens no Supabase client.
- `Features/Profile/ProfileSheet.swift` (PROF-01, STR-10) contains:
  - the large two-circle avatar, showing the initial or a person glyph
  - the "Name" field with a trailing Save that shows only when `hasNameChanged`, and a spinner while saving
  - the email, or "No email"
  - an outlined "Log out" in the error colour
  - a quiet "Delete account" button
  - the "Delete account?" alert (with the deletion body, Delete / Cancel) and the "Sign out?" alert (Sign out anyway / Cancel)

  All copy is Android's exact wording.
- `AppContainer` owns `profile: ProfileViewModel`, so sign-out and deletion finish after the sheet closes, like Android's application scope. `RootView` injects it through `\.profileViewModel`. It also shows the profile's snackbar when the sheet is closed, so "Your account has been deleted" appears on Welcome. `ListsView` (not owned) still calls `ProfileSheet(name:email:)` unchanged.
- NAV-04: no new code was needed. `StartSession` already goes to Welcome on `observeSignOuts`, and `RootView` already clears the stack on `.welcome`. A lost session is not a sign-out and stays put.

## Acceptance
- [x] `./scripts/verify.sh bgt-night-1 -only-testing:BabeGetThisTests/ProfileViewModelTests` gives `VERIFY PASS: 27 tests, 0 failures`, so executed ≥ 27. All 27 Android cases are ported by name.
- [x] `./scripts/verify.sh bgt-night-1` gives `VERIFY PASS: 1021 tests, 0 failures` (last run).

## Blocked
None.

## Follow-ups
- Toasts are a single "latest message" (`toast`), not a stream. Tests assert the last message rather than awaiting one event each.
- `DeferredProfileSync.hasUnsyncedChanges` treats an unreadable count as "unsynced", so it warns. Android would throw there instead.
- The profile uses `container.syncEngine` directly, not the engine injected through `start(syncEngine:)`. That injected engine only covers the trigger, so it is fine today, but integration tests that inject an engine won't see profile calls go to it.
- There are no UI tests for the sheet itself (alerts, Save visibility). Only the view model is unit tested.
- Mark PROF-01, PROF-02, PROF-03, NAV-04 and STR-10 as done in `docs/PARITY.md`. That file is outside this task's owned paths.
