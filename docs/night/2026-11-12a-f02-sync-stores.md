# F02: sync point store and list ownership store

## Summary
Ported `SyncPointStore`/`PrefsSyncPointStore` and `ListOwnershipStore`/`PrefsListOwnershipStore` to Swift
(`BabeGetThis/Core/Sync/Stores/`), backed by UserDefaults suites (`sync_points`, `list_ownership`).
Both protocols are `Sendable`. Android's `StateFlow<Int>` adoption notice becomes `adoptionNotice` (current value)
plus `adoptionNoticeUpdates()` (an `AsyncStream` that yields the current value first, then each change).
Tests ported 1:1 (4 + 7) as `SyncPointStoreTests` and `ListOwnershipStoreTests`, each with a unique suite removed in tearDown.

## Acceptance checklist
- SyncPointStoreTests, executed >= 4 (4 executed): done
- ListOwnershipStoreTests, executed >= 4 (7 executed): done
- Full suite: done

Last `./scripts/verify.sh bgt-night-2`: `VERIFY PASS: 133 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- The python `executed` check from the acceptance commands was not run by me (not on the allowed Bash list); the orchestrator runs it.
- Wire the stores into `AppContainer` when the SyncEngine port lands.
