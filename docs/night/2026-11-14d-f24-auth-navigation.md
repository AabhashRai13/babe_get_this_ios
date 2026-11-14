# F24: Auth navigation, account control, session-expired banner (night 2026-11-14d)

## Summary
- `AuthFlow` (`Features/Auth/AuthFlow.swift`) is a pure value type that holds the NAV-03 rules:
  - Login and Register replace each other; Forgot stacks on Login.
  - Close returns to the lists, or to Welcome if the lists aren't below.
  - Success always lands on the lists.
  - `AuthSheet` renders it: the root is Login or Register, Forgot password is pushed, and the
    sheet reports an `Exit`. The old `AuthSheet(initialRoute:onDone:)` initializer is kept, so
    ListDetail (not touched) still works.
- Welcome's "Sign in" opens the same `AuthSheet` over Welcome (`below: .welcome`). It replaces
  `SignInPlaceholderView`. Close returns to Welcome with nothing saved. Success closes the sheet
  and calls `StartSession.refresh()`, which drops Welcome.
- HOME-13: the lists' top bar shows Join, Settings, then the account control (`ListsViewModel.accountControl`).
  - When an account exists (including an expired session), the control is an initial avatar:
    the first letter of the name, else of the email, else a person glyph. Tapping it opens a
    placeholder `ProfileSheet` (name and email only) in `Features/Profile/`.
  - Otherwise it is a "Sign in" pill that opens Login.
- HOME-14: while `isSessionExpired` is true, a banner sits under the top bar with Android's text,
  "You've been signed out. Sign in again to keep your lists in sync.", and a "Sign in" button
  that opens Login.
- NAV-05: the gear now pushes a placeholder `SettingsView` (title "Settings") in every auth state.
- AUTH-11: the screen labels and layout moved into `LoginScreenCopy`, `RegisterScreenCopy` and
  `ForgotPasswordScreenCopy` (`Features/Auth/AuthScreenCopy.swift`), using Android's
  strings.xml wording. The views are built from them, so the view-model tests check what the
  screens actually render.
- Google and Apple sign-in are unchanged. `IdTokenSignInTests` passes as part of the full suite.

## Acceptance checklist
- [x] `./scripts/verify.sh bgt-night-1 -only-testing:BabeGetThisTests/AuthScreensTests` with at least 27 executed: done. Output: `VERIFY PASS: 27 tests, 0 failures`.
- [x] `./scripts/verify.sh bgt-night-1 -only-testing:BabeGetThisTests/AuthNavigationTests` with at least 8 executed: done. Output: `VERIFY PASS: 15 tests, 0 failures`.
- [x] `./scripts/verify.sh bgt-night-1`: done.

Last full run: `VERIFY PASS: 985 tests, 0 failures`

## Tests
- `BabeGetThisTests/Auth/Screens/AuthScreensTests.swift` (27) ports all 27 AuthScreensTest
  cases (Login 11, Register 8, Forgot 5, Auth prompt 3) as tests on the real view models over a
  fake repository (`AuthScreensFakes.swift`). No network.
- `BabeGetThisTests/Navigation/AuthNavigationTests.swift` (15):
  - 13 tests, one per NAV-03 rule or sub-case.
  - The BgtNavGraphTest name round-trip (line 103): a "Dad's / BBQ? #1" list created from the
    name dialog opens with the same id and exact name.
  - NAV-05: Settings opens for a guest, a signed-in user and an expired session.
- `BabeGetThisTests/Navigation/AccountControlTests.swift` (7) covers HOME-13 and HOME-14.

### Moves into AuthScreensTests
None. The existing tests in `BabeGetThisTests/Login/`, `Register/`, `ForgotPassword/` and
`AuthPrompt/` port Android's *ViewModel* tests (LoginViewModelTest and the others), not
AuthScreensTest. None of them is a faithful port of an AuthScreensTest case, so nothing was moved.
I also couldn't have moved them: those folders are outside this task's owned paths, so the
originals can't be deleted.

### BgtNavGraphTest cases not ported
- The 5 reminder cases: reminders are out of iOS v1.
- The create-list request cases at lines 112, 122 and 129 (`showListCatalog`,
  `applyPendingCreateList`): they serve Android's running-low notification, which iOS doesn't
  have. iOS doesn't behave the same way here, so per the brief there was nothing to port.

## Deviations
- On Android, Welcome's "Sign in" pushes Login onto Welcome's stack. On iOS it presents the
  same `AuthSheet` as a sheet over Welcome, following the brief's "keep that presentation". The
  NAV-03 outcomes are the same: Close comes back to Welcome, and success lands on the lists.
- On Android, the avatar initial comes from the name only. Following the brief, iOS falls back
  to the email's first letter.

## Blocked
- I couldn't delete `BabeGetThis/Features/Auth/SignInPlaceholderView.swift`. It is now unused,
  but `rm` and `git rm` aren't on the allowed command list and the Write tool can't delete files.

## Follow-ups
- Delete the unused `SignInPlaceholderView.swift`.
- F37: replace `ProfileSheet` with the real profile (edit name, sign out, delete account).
  `ListsViewModel.isProfilePresented` already closes the sheet once the account is gone.
- F42: fill in `SettingsView`.
- The Settings push uses `navigationDestination(isPresented:)` inside the lists'
  `NavigationStack(path:)`. If deep links to Settings are ever needed, move to a typed route
  enum in `RootView`.
- Mark NAV-03, NAV-05, HOME-13, HOME-14 and AUTH-11 done in `docs/PARITY.md` (not an owned path).
