# Task 2: Supabase rows and mappers
Branch `night/2-remote-dto`. Simulator `bgt-night-2`.

## Owned paths
- `BabeGetThis/Core/Remote/`
- `BabeGetThisTests/Remote/`
- `docs/night/2-remote-dto.md`

## Port from (Android, `origin/feat/got-this`)
`app/src/main/java/com/babegetthis/android/core/sync/data/model/SyncRows.kt` (`ListRow`, `ItemRow`),
`app/src/main/java/com/babegetthis/android/core/sync/data/mapper/SyncMappers.kt`, the test `SyncMappersTest` (17 cases),
checked against `supabase/migrations/001`–`006`.

## Acceptance (immutable)
- `Codable` `ListRow` and `ItemRow` with snake_case keys. `share_code`, `created_by` and the timestamps decode as nil when absent or null.
- ISO-8601 ↔ epoch-milliseconds helpers that match Android's `isoToMillis` / `millisToIso`.
- Mapping functions between rows and this task's own small local structs (defined in `Core/Remote/`; no dependency on task 1).
- 15 of the 17 `SyncMappersTest` cases ported and passing. The two `picked_up_at` round-trip cases
  ("picked up time travels as ISO…", "item row picked_up_at lands as millis…") are **not** ported. They are replaced by:
  (a) an encoded `ItemRow` **never contains the key `picked_up_at`**, not even as null; (b) decoding a server row
  that has `picked_up_at` succeeds and ignores it. (At least 17 `func test` in `BabeGetThisTests/Remote/`.)
- Pure Codable/Foundation; no network.
- `./scripts/verify.sh bgt-night-2` passes.
