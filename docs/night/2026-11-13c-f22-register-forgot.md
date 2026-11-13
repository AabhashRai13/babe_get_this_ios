# F22: Register and forgot-password screens

## Summary
Ported Android `RegisterViewModel` / `ForgotPasswordViewModel` and their screens to SwiftUI
(`@MainActor @Observable` view models, success via `onRegisterSuccess` / `onResetSuccess` closures,
errors shown through the shared `Snackbar`). The reset code is digits only, truncated to 8 (AUTH-04).
Register tracks the account-registered event only for `signedIn`, not `confirmationRequired`.
Navigation is not wired (F24). Tests use fake `AuthRepository` implementations; no network.

## Acceptance checklist
- RegisterViewModelTests, at least 9 executed: done (9)
- ForgotPasswordViewModelTests, at least 9 executed: done (9)
- Full suite `./scripts/verify.sh bgt-night-3`: done

Last verify line: `VERIFY PASS: 583 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- F24 must wire navigation and set `onRegisterSuccess` / `onResetSuccess`.
- Production `RegisterAnalytics` implementation (only a no-op exists here; owned paths prevented adding one to Core).
- The field-chrome helper is duplicated in the Register and ForgotPassword views because `LoginFieldChrome` is private to the Login file.
