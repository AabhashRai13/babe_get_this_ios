# Task 1: Local database (GRDB)
Branch `night/1-database`. Simulator `bgt-night-1`.

## Owned paths
- `BabeGetThis/Core/Database/`
- `BabeGetThisTests/Database/`
- `docs/night/1-database.md`

## Port from (Android, `origin/feat/got-this`)
`ShoppingListEntity`, `ShoppingItemEntity`, `CategoryEntity`, the shopping-list, item and category DAOs,
`DEFAULT_CATEGORIES` (`core/data/local/DefaultCategories.kt`, 49 entries with fixed IDs),
and the test `ShoppingListDaoTest` (23 cases). Find them with `ls-tree` + grep.

## Acceptance (immutable)
- GRDB `DatabaseMigrator` with migration `v1` creating `shopping_lists`, `shopping_items` (foreign key to the list,
  index on `listId`) and `categories`. Default categories are seeded once.
- Records keep the outbox fields: `pendingSync`, `onServer`, `accountId` (nil = guest), `deletedAt` (soft delete).
- `pickedUpAt` is **not** included (Got This is out of v1).
- Existing rows are always changed with UPDATE, never INSERT OR REPLACE. A test proves that updating a list keeps its items.
- All 23 `ShoppingListDaoTest` cases ported and passing, plus tests for item and category queries
  (at least 26 `func test` in `BabeGetThisTests/Database/`).
- Tests use an in-memory `DatabaseQueue`.
- `./scripts/verify.sh bgt-night-1` passes.
