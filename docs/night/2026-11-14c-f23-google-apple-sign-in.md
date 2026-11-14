# F23 report: Google sign-in and Sign in with Apple (run 2026-11-14c)

## Summary
- **AUTH-05** ("Generate a raw nonce, send its SHA-256 to Google, then pass the id token and raw nonce to Supabase `signInWithIdToken(provider: google)`. Cancelling is not an error. Offline fails before the sheet opens. Failure → "Google sign-in failed. Please try again."")
  - `Core/Auth/IdToken/IdTokenNonce.swift`: random raw nonce (UUID, like Android) and lowercase SHA-256 hex (CryptoKit).
  - `Core/Auth/IdToken/GoogleIdTokenRequester.swift`: the real `LoginGoogleTokenRequester`. It checks the client id first (not configured), then that the device is online (`NetworkMonitor`), then hashes the nonce and opens the sheet through the `GoogleSignInSheet` seam. The SDK's cancel error (`kGIDSignInErrorDomain`, `-5`) returns nil; any other error becomes `GoogleSheetFailure.failed`. `LiveGoogleSignInSheet` finds the key window's top view controller on the main actor at request time.
  - `SupabaseAuthRemote` now also conforms to the new `AuthIdTokenRemote` (`auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider:idToken:nonce:))`). `SupabaseAuthRepository` gets `signInWithGoogle` and `signInWithApple` (offline guard, session persisted like email login). Non-network failures read "Google sign-in failed. Please try again." and "Apple sign-in failed. Please try again.".
  - Not configured (iOS only): an empty or missing `GIDClientID`, or an unexpanded `$(...)` value, throws `GoogleSheetFailure.notConfigured` without calling the SDK. The login screen then shows "Google sign-in isn't set up in this build yet." and nothing is reported.
- **AUTH-06** ("Sign in with Apple, an iOS addition required by App Store rule 4.8. It uses the same nonce scheme through `signInWithIdToken(provider: apple)`, takes the full name from the first authorisation as `user_metadata.name`, and sits behind the same repository seam as Google.")
  - `Core/Auth/IdToken/AppleIdTokenSignIn.swift`: sets the scopes (`.fullName`, `.email`) and the hashed nonce on the request. It maps the result to a credential: `ASAuthorizationError.canceled` gives nil, and a missing token or any other error throws. A non-empty formatted name is kept.
  - `SupabaseAuthRepository.signInWithApple` signs in, then sends a non-blank name through the existing `updateUserName`. A failed name update keeps the sign-in.
  - Login screen: `SignInWithAppleButton` below the Google button at the same height and corner radius. It is black in light mode and white in dark. `LoginViewModel.prepareAppleSignIn()` / `completeAppleSignIn(_:)` reuse the same `signIn` path as Google, so a success sets the same loading state, sends the same analytics event and calls `onLoginSuccess`.
- Wiring: `AppContainer.makeLoginViewModel()` uses the real requester and the one `SupabaseAuthRepository` (on the shared `SupabaseClient`) for Google and Apple. I removed `GoogleSignInNotWired`. `BabeGetThisApp` handles the Google redirect with `.onOpenURL { GIDSignIn.sharedInstance.handle($0) }`.
- Tests: `BabeGetThisTests/Auth/IdToken/IdTokenSignInTests.swift`, 14 tests, with fake sheet, remote and Apple auth. No network calls and no real sheets. The existing `LoginViewModelTests` are unchanged and still pass. `LoginViewModel.init` only gained defaulted parameters.

## Acceptance
- [x] `verify.sh bgt-night-1 -only-testing:BabeGetThisTests/IdTokenSignInTests/testNonceIsSha256Hashed` (the Android FIPS vector `abc` is included)
- [x] `... /testCancelIsNotAnError`
- [x] `... /testAppleFullNameIsSentAsUserMetadataName`
- [x] `./scripts/verify.sh bgt-night-1`

Last verify (full suite): `VERIFY PASS: 936 tests, 0 failures`
(IdTokenSignInTests alone: `VERIFY PASS: 14 tests, 0 failures`)

## Blocked
- **Google nonce cannot reach Google with the pinned SDK.** GoogleSignIn-iOS **8.0.0** (in `Package.resolved`) has no `signIn(withPresenting:hint:additionalScopes:nonce:)`. I checked `GIDSignIn.h` in the package cache: no nonce parameter anywhere, and none on `GIDConfiguration` either. Later major versions add it. `Package.resolved` and `project.yml` are outside my owned paths, so the scheme is built behind the seam:
  - The requester always generates the raw nonce and passes its hash to `GoogleSignInSheet`.
  - `LiveGoogleSignInSheet` returns `nonceApplied: false` on 8.0.0.
  - The requester then sends an empty raw nonce, and the repository passes `nonce: nil` to Supabase. Supabase rejects a nonce that isn't in the token, so this is the only way Google sign-in works on 8.0.0.
  - Apple uses the full nonce scheme.
  - To finish this, upgrade the package, pass `hashedNonce` in `LiveGoogleSignInSheet`, and return `nonceApplied: true`. Nothing else changes; it is tested by `testNonceIsSha256Hashed` and `testTokenWithoutNonceSendsNoNonceToSupabase`.
- Bash denials (noted, not worked around): `grep -rn` and `ls` on the package cache outside the worktree, and `git grep -A`. I used the Read tool and plain `git grep` instead.

## Follow-ups
- Owner: add the Google iOS client (`BGT_GOOGLE_IOS_CLIENT_ID` / `BGT_GOOGLE_REVERSED_CLIENT_ID` in `Config/Secrets.xcconfig`) and enable the Google and Apple providers in each Supabase project. For Google, add the iOS client id to the provider's authorised client ids.
- Upgrade GoogleSignIn-iOS so the Google token carries the nonce (see Blocked).
- Apple's own sheet opens even when offline (the system button drives it), and the Supabase call then fails fast with "No internet connection." The brief's offline-before-sheet rule only covers Google.
- No real-device check of either sheet was possible tonight (no Google client, no signing).
- PARITY.md still marks AUTH-05/AUTH-06 as `[todo]`; that file is outside my owned paths.
