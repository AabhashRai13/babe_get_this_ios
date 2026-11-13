# F19: Supabase auth repository (night 2026-11-13a)

## Summary
This ports Android's `AuthRepository`, `SupabaseAuthRepository` and `AuthErrorMapper` into `BabeGetThis/Core/Auth/Repository/`.
- `AuthRepository.swift` holds the protocol, `AuthUser` and `AuthRegisterResult` (`signedIn` / `confirmationRequired`).
- `AuthRemote.swift` is the seam over supabase-swift (`AuthRemote` protocol plus `SupabaseAuthRemote`):
  - sign-up sends `user_metadata.name`
  - password sign-in
  - `resetPasswordForEmail`
  - `verifyOTP(type: .recovery)` for the 8-digit code
  - `update(user:)` for the name and the password
  - the `delete_user()` RPC
  - `signOut()`
  - User ids are lowercased UUID strings.
- `SupabaseAuthRepository.swift` follows Android method by method:
  - Every call except `logout` fails fast with `.network` when offline, and nothing reaches Supabase (AUTH-08).
  - Display name resolution follows AUTH-09: metadata name, else the fallback, else the email's local part.
  - Logout clears `AuthStateManager` first and then Supabase. It always succeeds, even when `/logout` fails (SESS-05).
  - Delete account checks for a session, calls the RPC, then clears in the same order as logout.
  - Cancellation is rethrown. A top-level `URLError.timedOut` becomes `.timeout`. A transport error anywhere in the cause chain becomes `.network`. Anything else becomes `.auth(friendly copy)`.
- `AuthErrorMapper.swift` maps errors to messages (AUTH-07):
  - Kotlin's cause chain is walked via `NSUnderlyingErrorKey`. URLError, POSIXError and the NSURL/POSIX domains count as transport errors.
  - Cycles are guarded by an identity set plus a depth cap.
  - The message rules and their order match Android. The raw provider text never passes through.

Tests (all in `BabeGetThisTests/Auth/Repository/`):
- `AuthErrorMapperTests` (16): all 15 Android tests ported, plus one that uses a real supabase-swift `AuthError.api`.
- `AuthRepositoryTests` (21): a fake remote and a fake network path, including `testEveryCallButLogoutFailsFastOffline`.
- `SupabaseAuthRemoteTests` (6): a URLProtocol stub checks the endpoints and payloads. It uses `http://127.0.0.1:54321` with a dummy key and makes no real network calls.

## Acceptance checklist
- [done] `verify.sh bgt-night-3 -only-testing:BabeGetThisTests/AuthErrorMapperTests`: `VERIFY PASS: 16 tests, 0 failures` (at least 15 needed).
- [done] `verify.sh bgt-night-3 -only-testing:BabeGetThisTests/AuthRepositoryTests/testEveryCallButLogoutFailsFastOffline`: `VERIFY PASS: 1 tests, 0 failures`.
- [done] `verify.sh bgt-night-3`: `VERIFY PASS: 400 tests, 0 failures`.

Final line of the last full `./scripts/verify.sh bgt-night-3`: `VERIFY PASS: 400 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- Nothing constructs the repository yet. It needs wiring in `AppContainer` (`SupabaseAuthRemote(client:)` plus the app's `AuthStateManager` and `NetworkMonitor`), which is outside my owned paths.
- Google and Apple sign-in (AUTH-05/06) are not part of F19. `AuthRemote` and `SupabaseAuthRepository` are the place to add `signInWithIdToken`; the mapper already has `googleSignInFailed`.
- `logout` relies on supabase-swift removing the stored session before it posts `/logout`. `SupabaseAuthRemoteTests.testAFailedSignOutStillClearsTheStoredSession` pins this, and it should be re-checked when supabase-swift is upgraded.
- When the RPC fails, deleteAccount shows generic copy ("Authentication failed. Please try again."), as Android does. A friendlier message would be a product decision.
