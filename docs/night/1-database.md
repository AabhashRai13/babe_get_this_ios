# Night task 1: Local database (GRDB)

## Summary
Ported the Android Room layer (`origin/feat/got-this`) to GRDB 7.12 in `BabeGetThis/Core/Database/`:

- `AppDatabase`: owns `any DatabaseWriter`, runs a `DatabaseMigrator` with migration `v1`, and exposes
  `lists`, `items` and `categories` DAOs. `inMemory()` is for tests and `onDisk()` uses a `DatabasePool` in Application Support.
- `v1` creates `shopping_lists`, `shopping_items` (FK `listId` → `shopping_lists.id` ON DELETE CASCADE,
  index `index_shopping_items_listId`) and `categories`. It seeds `DefaultCategories.all` inside the migration,
  so seeding happens once.
- Records `ShoppingListRecord`, `ShoppingItemRecord`, `CategoryRecord` and `ShoppingListWithItemCount` use
  the Android column names. Timestamps are `Int64` epoch milliseconds. The outbox fields are kept:
  `pendingSync`, `onServer`, `accountId` (nil = guest), `deletedAt`, plus `shareCode` and `isLocked`. There is no `pickedUpAt`.
- `ShoppingListDao` is a port of every Android query, including sync primitives, claim-on-sign-in (`claimDeviceLists`
  in one transaction) and sign-out eviction. `ShoppingItemDao` drops only the Got This queries.
  `CategoryDao` is a straight port. DAO methods are `async throws`. The Flow queries also have
  `observe…` methods that return a `ValueObservation`.
- No INSERT OR REPLACE anywhere. `insertList`/`insertItem` do a plain INSERT, which throws on an existing id.
  `saveList`/`saveItem(s)`/`insertListWithItems` UPDATE an existing row and INSERT only when it's missing (GRDB `save`).
  `updateList`/`updateItem` do UPDATE. Category inserts use INSERT OR IGNORE, like Android.

## Acceptance checklist
- [done] GRDB `DatabaseMigrator`, migration `v1` with the three tables, the FK and the `listId` index. Defaults are seeded once
  (`testDefaultCategoriesAreSeededByTheMigration`, `testMigratingAgainDoesNotSeedTwice`, `testSchemaHasTheOutboxColumnsAndNoPickedUpAt`).
- [done] Records keep `pendingSync`, `onServer`, `accountId` (nil = guest) and `deletedAt`.
- [done] No `pickedUpAt`. A schema test asserts that the column is absent.
- [done] Existing rows are changed with UPDATE, never INSERT OR REPLACE. `testUpdatingAListKeepsItsItems` proves that a list keeps its items.
- [done] All 23 `ShoppingListDaoTest` cases are ported and pass. Android's `insertList replaces on conflicting id` became
  `testSaveListUpdatesOnConflictingId`, because iOS never REPLACEs. Item and category query tests were added too.
  `BabeGetThisTests/Database/` has 44 `func test` (30 list, 7 item, 7 category).
- [done] Tests use an in-memory `DatabaseQueue` (`AppDatabase.inMemory()`).
- [done] `./scripts/verify.sh bgt-night-1` passes. Last run, final line: `VERIFY PASS: 64 tests, 0 failures`

## Blocked
Nothing.

## Notes / discrepancies
- The brief says `DEFAULT_CATEGORIES` has 49 entries. On both `origin/feat/got-this` and `origin/main`,
  `DefaultCategories.kt` has **48** (`git grep -c "CategoryEntity(id"` → 48). Android is the spec, so the port has the
  same 48 entries and the tests assert 48.

## Follow-ups
- Wire `AppDatabase.onDisk()` into `AppContainer`. That file is outside this task's owned paths.
- Got This item queries were not ported, because Got This is out of v1: `tickedWithoutTime`, `setPickedUpAt`, `uncheckedNames`,
  `lockedItemIds` and `namesCreatedSince`. `setPickedUp` has no `pickedUpAt` parameter.
- The `observe…` `ValueObservation` methods compile but have no tests of their own. They share their fetch
  functions with the tested one-shot reads.
