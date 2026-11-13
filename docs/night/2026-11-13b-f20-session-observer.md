# F20: Session observer and bearer/401 handling (2026-11-13b)

## Summary
- `BabeGetThis/Core/Auth/Session/SessionObserver.swift`: port of Android `SessionObserver`.
  - `SupabaseSessionStatus` mirrors supabase-kt `SessionStatus`. `from(event:session:)` maps supabase-swift `AuthChangeEvent`s:
    - `signedOut` → notAuthenticated
    - an event with a session → authenticated
    - `initialSession` with no session → notAuthenticated
  - Authenticated → `refreshToken` plus telemetry user id. NotAuthenticated → `expireSession()` (never logout) plus telemetry nil. RefreshFailure and Initializing do nothing.
  - The work runs on a `SessionObserverScheduler`, which is the stand-in for Android's IO dispatcher. By default this is a serial utility queue, so changes are applied in order.
  - `AuthStateManager` conforms to the new `SessionAuthStateSink` protocol. Telemetry is reached through `SessionTelemetryIdentity`, which is a no-op for now (no TelemetryContext exists yet).
- `BabeGetThis/Core/Voice/TranscribeBearerAuth.swift`: port of `AuthInterceptor` + `AuthAuthenticator`.
  - Adds the bearer header only when a token exists, and replaces any existing header.
  - A 401 on a request that carried a bearer calls `expireSession()`. There is no retry and no refresh.
- `TranscribeClient` now takes `auth: TranscribeBearerAuth` instead of an `accessToken` closure.
  - With no token, the request goes out without a header (Android behaviour). Before, the client threw `.unauthorized` without sending anything.
  - `URLError(.cancelled)` counts as cancellation only when `Task.isCancelled` is true (the SafeCall rule). Two tests were added for this to TranscribeClientTests.

## Acceptance
- [done] `verify.sh bgt-night-4 -only-testing:BabeGetThisTests/SessionObserverTests`: 8 tests (>= 7), 0 failures
- [done] `verify.sh bgt-night-4 -only-testing:BabeGetThisTests/AuthNetworkTests`: 9 tests (>= 9), 0 failures
- [done] `verify.sh bgt-night-4`: full suite

Last full run: `VERIFY PASS: 478 tests, 0 failures`

## Notes on the port
- Android mocks `AuthStateManager` to check that `logout()` is never called. Here those tests use a real `AuthStateManager` + `InMemoryTokenStore` instead and assert:
  - the state stays `.authenticated` (or becomes `.sessionExpired`, never `.unauthenticated`);
  - the user id is kept.
  This is stricter than the mock check.
- "Request otherwise untouched" and "caller-supplied Authorization overwritten" send a custom request through the real stub `URLSession` using `authorize`/`handle`. The other AuthNetworkTests go through `TranscribeClient`.

## Blocked
- None.

## Follow-ups
- Wire it up in `AppContainer` (not an owned path):
  - build `TranscribeClient` with `TranscribeBearerAuth(tokenStore:authStateManager:)`;
  - call `SessionObserver(authState: authStateManager).observe(auth: supabaseClient.auth)` once at launch.
- Once TEL-02/TelemetryContext lands, have `TelemetryContext` conform to `SessionTelemetryIdentity`.
- `SupabaseSessionStatus.from(event:session:)` has no unit test, because supabase-swift `Session` values are awkward to build in tests.
