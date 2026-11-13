# F21 Login screen and view model (2026-11-13b)

## Summary
- `LoginViewModel` (`@MainActor @Observable`): form state, email validation (Android regex), email login, Google flow, double-tap guard, `onLoginSuccess` callback, analytics (no payload) and crash reporting of failing Google sheets as `.unknown`.
- `LoginView`: real login screen (brand mark, form card, show/hide password, forgot password, sign in, Continue with Google, sign-up link, close). Uses `AppColors`, `AppMetrics`, `PrimaryButtonStyle`, `OutlinedButtonStyle`. Navigation is by closures only.
- `LoginGoogleSupport.swift`: `GoogleSignInToken`, `GoogleSheetFailure`, protocols `LoginGoogleTokenRequester`, `LoginGoogleAuthenticating`, `LoginAnalytics`, and `LoginEmailValidator`.
- `LoginViewModelTests`: 19 tests, a port of Android `LoginViewModelTest` plus a few extras.

## Acceptance checklist
- LoginViewModelTests run, executed >= 15: done (19)
- Full suite: done

Last `./scripts/verify.sh bgt-night-5`: `VERIFY PASS: 478 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- `SignInPlaceholderView` is unchanged: `AppContainer` (App/, owned by F24) has no auth repository, so it can't build a `LoginViewModel` yet. F24 should show `LoginView(viewModel:)` and wire `onLoginSuccess`, register, forgot password and close.
- The Android `AuthRepository.signInWithGoogle` is not on the iOS `AuthRepository` protocol (Core/Auth is read-only here), so Google uses the separate `LoginGoogleAuthenticating` protocol. A real `LoginGoogleTokenRequester` (GoogleSignIn-iOS, offline check) and the Supabase ID-token exchange still need to be written.
- Google logo is the SF Symbol `g.circle`; the Android `ic_google_logo` asset isn't ported.
- The error is shown in an alert; Android uses a snackbar.
- No Apple sign-in here (not in the Android login screen).
