# Overnight run: five parallel tasks (2026-11-11)

## Goal
Make real progress on the iOS port overnight without the owner. Five tasks run in parallel, each proved by
tests. Nothing is pushed, nothing touches prod, nothing in `android/` changes. In the morning the owner gets
five branches, one local integration branch and a report.

## Owner's constraints
- Five tasks, not fifty. They run without approval, so every task is fully specified here.
- **No Claude trailer** (`Co-Authored-By`, "Generated with Claude") in any commit or PR.
- Never `git push`. Never merge into `main` without the owner's yes.
- `android/Babe-get-this` is read-only. Read `feat/got-this` with `git show origin/feat/got-this:<path>`;
  never check it out.
- Never touch production Supabase (`fpzjyusgqdzqituokrwq`). Don't stop or reset the running local
  `babe-get-this` stack. No task tonight needs Supabase.

## Execution model: five Claude Code sessions in git worktrees

### Prep (done by the orchestrating session on `main`, before anything starts)
1. `project.yml`: add the Swift packages GRDB.swift and supabase-swift. No session edits `project.yml`.
2. `scripts/verify.sh <simulator-name>`: runs `xcodegen generate`, then `xcodebuild test` into `./build`, and
   prints only compiler errors, failing tests and the final test count. Exits non-zero on failure.
3. `.claude/settings.json`: add an allow list for `xcodebuild`, `xcodegen`, `xcrun simctl`, `swift`, `./scripts/verify.sh`,
   and git `add`/`commit`/`status`/`diff`/`log`/`show`. Keep the existing denies (push, `android/`, prod ref).
4. Empty folders with a `.gitkeep` for each task's area.
5. Five worktrees at `../ios-night/<n>-<task>` on branches `night/<n>-<task>`, cut from that prep commit.
6. Four cloned simulators named `bgt-night-<n>` (cloned from `iPhone 18 Pro`). Task 5 needs none.

### Rules every session follows
- Test first. A task is done when its acceptance list passes and `scripts/verify.sh bgt-night-<n>` is clean.
- Touch only the task's own paths plus `docs/night/<n>-<task>.md`.
- Commit locally after each green step, with plain messages and no trailer lines. No push.
- **Stuck rule:** after three failed attempts at the same problem, write it under "Blocked" in the task report,
  commit whatever passes, and stop. Never wait for input.
- **No extras:** stop at the acceptance list. Anything else goes under "Follow-ups" in the report.
- The task report lists: what was done, real test counts, what's blocked, follow-ups.

## The five tasks

### 1. Local database (GRDB): `night/1-database`
- **Owns:** `BabeGetThis/Core/Database/`, `BabeGetThisTests/Database/`.
- **Port from:** `ShoppingListEntity`, `ShoppingItemEntity`, `CategoryEntity`, the shopping-list, item and category DAOs,
  `DEFAULT_CATEGORIES` (49 entries with fixed IDs).
- **Acceptance:**
  - GRDB `DatabaseMigrator` with migration `v1` creating `shopping_lists`, `shopping_items` (foreign key to the list,
    index on `listId`) and `categories`. Default categories are seeded once.
  - Records keep the outbox fields: `pendingSync`, `onServer`, `accountId` (nil = guest), `deletedAt` (soft delete).
  - `pickedUpAt` is **not** included (Got This is out of v1).
  - Existing rows are always changed with UPDATE, never INSERT OR REPLACE. A test proves that updating a list
    keeps its items.
  - All 23 `ShoppingListDaoTest` cases ported and passing, plus tests for item and category queries.
  - Tests use an in-memory `DatabaseQueue`.

### 2. Supabase rows and mappers: `night/2-remote-dto`
- **Owns:** `BabeGetThis/Core/Remote/`, `BabeGetThisTests/Remote/`.
- **Port from:** `core/sync/data/model/SyncRows.kt` (`ListRow`, `ItemRow`) and
  `core/sync/data/mapper/SyncMappers.kt`, checked against migrations 001–006.
- **Acceptance:**
  - `Codable` `ListRow` and `ItemRow` with snake_case keys. `share_code`, `created_by` and the timestamps decode
    as nil when absent or null.
  - ISO-8601 ↔ epoch-milliseconds helpers that match Android's `isoToMillis` / `millisToIso`.
  - Mapping functions between rows and the task's own small local structs (no dependency on task 1).
  - 15 of the 17 `SyncMappersTest` cases ported and passing. The two `picked_up_at` round-trip cases
    ("picked up time travels as ISO…", "item row picked_up_at lands as millis…") are **not** ported. They are
    replaced by: (a) an encoded `ItemRow` **never contains the key `picked_up_at`**, not even as null;
    (b) decoding a server row that has `picked_up_at` succeeds and ignores it. iOS v1 is a pre-Got-This
    client, so the migration 006 trigger records legacy ticks.

### 3. Voice transcribe client: `night/3-voice-client`
- **Owns:** `BabeGetThis/Core/Voice/`, `BabeGetThisTests/Voice/`.
- **Port from:** `core/voice/data/remote/dto/TranscribeDtos.kt` and `RemoteVoiceRepository` (+ its test).
- **Acceptance:**
  - `TranscribeClient` sends `POST {apiBaseURL}transcribe` as `multipart/form-data` with a part named `audio`,
    filename `*.m4a`, content type `audio/mp4`. Header `Authorization: Bearer <token>`. 60-second timeout.
  - Response `{transcript?, items:[{name, quantity:Int?, unit?, category?, location?, note?}]}` maps to
    parsed items. Quantity and unit are merged into one string (same rules as Android); `location` becomes `shop`.
  - HTTP and decoding errors map to the same categories Android uses.
  - All 12 `RemoteVoiceRepositoryTest` cases ported, using a `URLProtocol` stub (no real network).
  - No recording or UI.

### 4. List detail screen: `night/4-list-detail`
- **Owns:** `BabeGetThis/Features/ListDetail/`, `BabeGetThisTests/ListDetail/`, `docs/night/screens/`.
- **Port from:** `ShoppingItemsScreen`, its components and `ShoppingItemsViewModel`, plus `docs/screenshots/02-sunday-roast.png`.
- **Acceptance:**
  - Replaces `ListDetailPlaceholderView` (same name, same `list:` initializer, so `ListsView` is unchanged).
  - Progress card ("3 of 7 picked up", percentage, bar). ACTIVE ITEMS grouped by shop, then category. COMPLETED section below.
  - Item card: tick circle, name, italic note, quantity and category chips in the brand colours.
  - Tick/untick moves an item between Active and Completed. Swipe to delete with an Undo snackbar.
  - Add-item sheet: name (required), quantity (required), category picker, shop, note.
  - An in-memory `@Observable` view model with unit tests for grouping, progress, tick, delete/undo and add validation.
  - Uses `AppColors` and `AppMetrics` only (no hex values in views).
  - Light and dark screenshots of the screen with sample data saved to `docs/night/screens/`.

### 5. Parity spec and task list: `night/5-parity`
- **Owns:** `docs/PARITY.md`, `harness/features.json`.
- **Reads:** Android `docs/technical-decisions/*`, `docs/product-decisions/*`, `docs/superpowers/specs/*`,
  migrations 001–006, `REALTIME_TEST_FINDINGS.md`, screens, strings and the sync code (from `feat/got-this`).
- **Acceptance:**
  - `PARITY.md`: every v1 screen, behaviour, user-facing string and sync/sharing/realtime rule, each with an ID
    (for example `SYNC-07`) and its Android file reference. Out-of-v1 features are listed as excluded.
  - `features.json`: about 45 tasks in dependency order. Each task has `id`, `title`, `parity_ids`, `depends_on`,
    `acceptance` (shell commands) and `status: "todo"`. It excludes what already exists on `main` and what tasks 1–4 deliver.
  - Docs only. No Swift changes.

## Integration and morning report (orchestrating session)
1. **No polling:** the app wakes the orchestrating session as each session finishes. If a session messages
   that it's blocked, the orchestrator answers from this spec or tells it to log and stop. It never makes the owner's decisions.
2. **Check each branch:** diff it against `main` and confirm it changed only its own paths and has no trailer lines.
   Rerun `verify.sh` and record the real test counts. If tests fail, rerun them alone once to rule out
   interference from parallel builds.
3. **Merge:** cut `night/integration` from `main` and merge passing branches in the order 2, 1, 3, 4, 5. A failing
   or conflicting branch is left out and noted.
4. **Verify:** full test suite on `night/integration`, plus a simulator run of the list detail screen in light and dark mode.
5. **Report:** `docs/night/2026-11-11-report.md` with a table (task, branch, tests, status), blocked items,
   follow-ups, decisions for the owner, and the next five suggested tasks from `features.json`. Committed on
   `night/integration`.

## Morning (owner)
Read the report, choose the branches to merge into `main`, and review `PARITY.md` and `features.json`
(the "Night 0" review from the handoff).

## Risks
| Risk | Mitigation |
|---|---|
| A session stalls on a permission prompt | Allow list in `.claude/settings.json`; the sessions run in auto mode |
| Four `xcodebuild`s at once are slow or flaky | Separate build folders and simulators; a failing test is rerun alone before the branch is marked failed |
| A session goes off scope | The scope diff in integration step 2 excludes the branch |
| Usage limit reached | Sessions resume after the reset; unfinished work is listed in the report |
| Mac sleeps | Request keep-awake from the app; Mac stays plugged in |
| Tasks 1 and 2 define different local record types | Intentional for tonight; they're unified in the SyncEngine task after review |
