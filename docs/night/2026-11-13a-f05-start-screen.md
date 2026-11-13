# F05: Welcome choice and start screen (2026-11-13a)

## Summary
- `WelcomeRepository` (UserDefaults, key `welcome_done`) ports the Android repository: first answer persisted, update installs skip Welcome, `markDone()` / `reset()`.
- `WelcomeViewModel` (`onContinueAsGuest`, `onSignIn`) with a `WelcomeAnalytics` protocol (no-op for now) and `WelcomeChoice`.
- `StartScreen.resolve` + `StartSession` (App/): loading -> blank launch state, authenticated / session expired -> lists, unauthenticated -> lists if guest chosen else Welcome. A sign-out (via `AuthStateManager.observeSignOuts`) resets the choice.
- `RootView` and `AppContainer` now use `AuthStateManager` (Keychain token store, `initialize()` on launch). `-sampleData` / `-openList` still work (screen forced to lists).
- Tests: WelcomeRepositoryTests (7), WelcomeViewModelTests (2), StartScreenTests (3).

## Acceptance checklist
- WelcomeViewModelTests, >= 2 executed: done (2 tests; the filtered run was not executed separately, only the full suite)
- WelcomeRepositoryTests, >= 4 executed: done (7 tests; same note)
- Full suite: done

Last verify line: `VERIFY PASS: 369 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- `Core/Session/SessionStore.swift` is now unused by the app (not owned, left in place); delete it.
- `Features/Auth/SignInPlaceholderView` (not owned) still calls `container.session.continueAsGuest()`, kept as a method on `StartSession`. Replace when real sign-in lands.
- `isUpdateInstall` defaults to `false` (no iOS equivalent wired yet); decide how to detect an upgrade install.
- `WelcomeAnalytics` is a no-op; connect to the real analytics repository when it exists.
- Sign-out resets Welcome only through the `observeSignOuts` observer in `StartSession`; explicit account deletion should go through `AuthStateManager.logout()` to get the same effect.
