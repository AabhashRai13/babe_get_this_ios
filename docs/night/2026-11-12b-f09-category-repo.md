# F09: CategoryRepository (night 2026-11-12b)

## Summary
Ported Android `CategoryRepository` to `BabeGetThis/Core/Repositories/Category/CategoryRepository.swift`:
`allCategories()` (live `AsyncThrowingStream` over the DAO's `ValueObservation`), `addCategory(name:)`
(trimmed, blank rejected with `AppError.validation`, new lowercase UUID, never default) and
`deleteCategory(id:)` (success even for defaults or unknown ids, as on Android). Both wrap in `SafeCall`.
Added the domain type `ProductCategory` with `toDomain()` / `toRecord()` mappers.

`CategoryRepositoryTests` has 24 tests: all 22 of Android `CategoryDataTest`, plus 2 extras (empty-name
message, observation emits on add). The iOS migration seeds the 48 defaults, while Android's
in-memory DB starts empty, so `setUp` clears the `categories` table to match the Android fixture.

## Acceptance checklist
- `verify.sh bgt-night-2 -only-testing:BabeGetThisTests/CategoryRepositoryTests`, executed >= 22: done (24 executed)
- `verify.sh bgt-night-2` full suite: done

## Verify output (last lines)
- Class run: `VERIFY PASS: 24 tests, 0 failures`
- Full suite: `VERIFY PASS: 206 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- Wire `CategoryRepository` into `AppContainer` (outside owned paths).
- `UUID().uuidString.lowercased()` matches Android's `UUID.randomUUID().toString()` format.
