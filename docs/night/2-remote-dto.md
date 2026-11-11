# Night task 2: Supabase rows and mappers

## Summary
Ported Android `SyncRows.kt` and `SyncMappers.kt` (origin/feat/got-this) into `BabeGetThis/Core/Remote/`:

- `SyncRows.swift`: `ListRow` and `ItemRow`, `Codable` with snake_case keys that match migrations 001–006.
  Optional fields decode as nil when they are absent or null. `is_picked_up` defaults to false.
  Encoding writes nil as an explicit JSON `null`, matching Android's `encodeDefaults = true, explicitNulls = true`.
  `ItemRow` has no `picked_up_at` field, so the key is never encoded and is ignored when decoding.
- `SyncMappers.swift`: `String.isoToMillis()` (throws) and `Int64.millisToIso()`. They behave like kotlinx
  `Instant.parse(...).toEpochMilliseconds()` and `Instant.fromEpochMilliseconds(...).toString()`: `Z` or a
  numeric offset, a fraction of 1–9 digits floored to milliseconds, and output with a 3-digit fraction only
  when it is non-zero. The helpers do their own date arithmetic, so neither DateFormatter nor the locale is involved.
  The mappers are `LocalListRecord.toRow(createdBy:)`, `LocalItemRecord.toRow()`,
  `ListRow.toRecord(local:accountId:lockedIds:)` and `ItemRow.toRecord(local:)`. A row with no `updated_at`
  throws `SyncMappingError.missingServerClock`, where Android throws `IllegalArgumentException`.
- `LocalRecords.swift`: `LocalListRecord` and `LocalItemRecord`, plain copies of Android's
  `ShoppingListEntity` and `ShoppingItemEntity` without `pickedUpAt`. They have no dependency on task 1.

Tests: `BabeGetThisTests/Remote/SyncMappersTests.swift` has 17 tests: the 15 ported Android cases and the
2 `picked_up_at` replacements. `SyncRowsTests.swift` has 8 tests covering decoding when fields are absent or
null, explicit-null encoding, PostgREST microsecond timestamps, offsets, negative epochs and malformed input.

## Acceptance
- [done] `Codable` `ListRow` and `ItemRow` with snake_case keys. `share_code`, `created_by` and the timestamps decode as nil when absent or null.
- [done] ISO-8601 ↔ epoch-milliseconds helpers that match Android's `isoToMillis` / `millisToIso`.
- [done] Mapping functions between the rows and this task's own local structs in `Core/Remote/`, with no dependency on task 1.
- [done] 15 of the 17 `SyncMappersTest` cases ported and passing. The `picked_up_at` round trips are replaced by
  (a) `testEncodedItemRowNeverContainsPickedUpAt` and (b) `testDecodingIgnoresPickedUpAt`.
  `BabeGetThisTests/Remote/` has 25 `func test` in total.
- [done] Pure Codable/Foundation; no network.
- [done] `./scripts/verify.sh bgt-night-2` passes.

## Last verify
`VERIFY PASS: 45 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- The sync engine has to convert between `LocalListRecord` / `LocalItemRecord` and task 1's GRDB records.
  When it applies a server item, it should keep the local `pickedUpAt` column as it is, if that column exists,
  because iOS v1 ignores the server's `picked_up_at`.
- `isoToMillis` also accepts `t` as the date/time separator and `,` as the decimal mark. Neither appears in
  Supabase output.
