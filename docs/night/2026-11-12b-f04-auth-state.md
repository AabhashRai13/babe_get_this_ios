# F04 auth state: night 2026-11-12b report

## Summary
Ported Android `AuthState`, `TokenManager` and `AuthStateManager` (parity SESS-01, SESS-02, SESS-04).

- `BabeGetThis/Core/Auth/AuthState.swift`: `AuthState` enum (`loading`, `authenticated(userId:)`,
  `sessionExpired(userId:)`, `unauthenticated`) and `ownerId`.
- `BabeGetThis/Core/Auth/TokenStore.swift`:
  - `TokenStore` protocol.
  - `KeychainTokenStore`: generic passwords, service = bundle id, accounts `auth_token` / `user_id` / `user_name` / `user_email`,
    `AfterFirstUnlockThisDeviceOnly`.
  - `InMemoryTokenStore` fake.
  - `clear()` deletes only its four accounts, so a later PIN store under the same service survives a sign-out. This is the iOS
    counterpart of Android's separate prefs files.
- `BabeGetThis/Core/Auth/AuthStateManager.swift`:
  - `@Observable`, `@unchecked Sendable`. Every transition runs under one `NSRecursiveLock`, matching Android's `@Synchronized`.
  - `initialize` / `login` / `refreshToken` / `expireSession` / `logout` / `updateName` / `currentEmail`, `dataOwnerId`,
    `liveSessionUserId`.
  - Android's `dataOwner` and `signOuts` flows became `observeDataOwner(_:)` / `observeSignOuts(_:)`. These are synchronous
    handlers that return an `AuthStateSubscription`, so the tests can check exact sequences the way Turbine does. They also
    have `AsyncStream` wrappers (`dataOwner`, `signOuts`).
  - Like a StateFlow, an unchanged state notifies nobody.
- Tests:
  - `AuthStateManagerTests`: all 28 Android tests plus 2 iOS-only tests (the stream wrapper and cancellation). The
    background-thread race test is ported with a `Thread` plus a `DispatchGroup` with a 200 ms wait.
  - `TokenStoreTests`: these run against the real Keychain in the simulator, and Keychain worked (no -34018). Six are ports of
    the Android tests: fresh store, round-trip, overwrite, clear wipes everything, second instance, and clear leaves other
    items alone. The Android test where the Keystore key is gone became "an unreadable item reads as nil". There are 2 extra
    tests: clearToken keeps the identity, and the default service is the bundle id.
  - Android mocks TokenManager in the first test group; here those tests use `InMemoryTokenStore` and check what it stored.

## Acceptance
- [done] `verify.sh bgt-night-1 -only-testing:BabeGetThisTests/AuthStateManagerTests`: `VERIFY PASS: 30 tests, 0 failures` (≥ 28)
- [done] `verify.sh bgt-night-1 -only-testing:BabeGetThisTests/TokenStoreTests`: `VERIFY PASS: 9 tests, 0 failures` (≥ 7; latest.json `executed: 9`)
- [done] `verify.sh bgt-night-1`: `VERIFY PASS: 221 tests, 0 failures`

## Blocked
None.

## Follow-ups
- Wire `AuthStateManager(tokenStore: KeychainTokenStore())` into `AppContainer` and replace the `SessionStore`
  placeholder. Call `initialize()` at launch. This is a later task.
- SESS-03 (SessionObserver → `refreshToken` / `expireSession`) and SESS-05 (sign-out order) build on this.
- `InMemoryTokenStore` lives in the app target so that previews and `-sampleData` can use it.
