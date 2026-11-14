# F30: SyncTrigger (2026-11-14b)

## Summary
- `BabeGetThis/Core/Sync/Trigger/SyncTrigger.swift`: port of Android `SyncTrigger.kt`, behind the protocol
  `SyncTriggerEngine` (push, catchUpAccount, onAuthState; `SyncEngine` conforms as-is).
  - `kick()` = `push()` then `catchUpAccount()` on a detached task. Results are dropped. No debounce, no timer.
  - `pushSoon()` only pushes. The trigger is the app's real `SyncKicking`.
  - Auth states reach the engine in order (each state's work waits for the one before). A state kicks when
    `onAuthState` returns true.
  - Network: `SystemNetworkAvailability` (its own `NWPathMonitor`) fires on every move to a satisfied path,
    including the first path at registration. I left `NetworkMonitor` alone because `Core/Network` is outside
    my owned paths and it has no change callback.
  - Lifecycle: `scenePhaseChanged(_:)` kicks only on background → active (or on the first active). Moving
    between inactive and active does not kick.
- `SyncTriggerSources.swift`: `AuthStateManager` conforms to `AuthStateStream` through Observation (current
  value first, then each change, like a StateFlow collector). I did this because `AuthStateManager` (outside
  my owned paths) has no public "every state" observer.
- `AppContainer`:
  - `NoOpSyncKicker()` is replaced by `syncTrigger` in both repositories.
  - `ShoppingListRepository` gets `catchUp: { engine.catchUp(listId:) }` (DATA-06).
  - The "F30 wires it" comments are gone.
  - New `start(syncEngine:network:)` registers the trigger, then calls `authState.initialize()`. `live()`
    calls it. Before `start()` the trigger resolves no engine, so test containers and `-sampleData` (never
    started) build no Supabase client and never touch the network. The engine is still built lazily.
- `BabeGetThisApp`: `.onChange(of: scenePhase, initial: true)` passes the phase to the trigger.

Parity:
- **TRIG-01** "kick() = push() then catchUpAccount(), on a detached task. Results are discarded. No debounce and no timer; duplicate kicks are harmless. Port SyncTriggerTest (7)."
- **TRIG-02** "A kick fires on: an auth transition where onAuthState returns true (this includes launch while signed in); network becoming available, including at registration; the app becoming active (scenePhase)."
- **APP-05** "App start: sync trigger registered, auth state restored before the first screen decision. (Android also fetches feature flags here; flags are out of v1, FLAG-01.)"

I did not edit `docs/PARITY.md` because it is outside my owned paths. These three can be marked done.

## Acceptance
- [done] `SyncTriggerTests`: 9 executed. These are the 7 Android cases, plus "no engine means no kick" and a check that the `AuthStateManager` stream starts with the current state and follows changes.
- [done] `AppStartTests/testAuthIsRestoredBeforeTheFirstScreenDecision` passes. `testLaunchingSignedInKicksASync` is also in the class.
- [done] Full suite.

Last `./scripts/verify.sh bgt-night-1`: `VERIFY PASS: 892 tests, 0 failures`

## Blocked
None.

## Follow-ups
- Mark TRIG-01, TRIG-02 and APP-05 done in `docs/PARITY.md`.
- `NetworkMonitor` and `SystemNetworkAvailability` each run their own `NWPathMonitor`. One shared monitor with a change callback in `Core/Network` would remove the duplicate.
- An `AuthStateManager.observeAuthStates` API in `Core/Auth` (a plain observer, like `observeDataOwner`) would replace the Observation-based adapter, which can merge a quick burst of changes into its last value.
