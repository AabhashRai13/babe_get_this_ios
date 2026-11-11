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

## Execution model: five headless Claude Code workers in git worktrees

> Superseded in part by **Reliability amendments** below: a deterministic shell runner (`harness/night/run-night.sh`)
> launches the five workers as `claude -p` processes, not as desktop-app sessions. Tasks, scope and acceptance are unchanged.

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

## Reliability amendments (owner, 2026-11-11)
These change *how* the night runs. The five tasks, their scope, their acceptance criteria and the prohibitions
(no prod, no push, no `android/` edits, no merge into `main`) are unchanged.

### R1 Orchestration
`harness/night/run-night.sh` is the only orchestrator. It runs `preflight.sh` and aborts if that fails. Then it
starts five `claude -p` workers, one per worktree, with `--output-format stream-json`, `--no-session-persistence`
and a per-task model, budget and timeout. It waits for all of them and records each exit code and final result
event in `../ios-night/_state/`. Then it runs `integrate.sh`. Everything runs under `caffeinate -dimsu`.
No orchestration depends on a live chat session.

### R2 Build concurrency
At most **two** `xcodebuild` processes at once, machine-wide. `scripts/verify.sh` takes one of two lock slots
(an atomic `mkdir` lock holding the owner's PID; a lock is reclaimed only if that PID is dead) before building. Workers can't
call `xcodebuild` directly (denied in settings). Each worktree has its own DerivedData (`build/DerivedData`),
its own result bundle per run (`build/results/<timestamp>.xcresult`) and its own simulator (`bgt-night-<n>`); the
orchestrator verifies on `bgt-night-verify`. Swift packages are resolved once in preflight into a shared
read-only directory. Builds pass `-clonedSourcePackagesDirPath` and `-disableAutomaticPackageResolution`, so
workers need no network.

### R3 Permissions, sandbox and credentials
- Workers run with `--permission-mode dontAsk --permission-prompts none` (anything not allowed is denied) and
  `--setting-sources project` plus a per-task `--settings` file. `--strict-mcp-config` means no MCP servers, and
  slash commands and skills are disabled. No user plugins or hooks are loaded.
- Writes are allowed only in the task's owned paths and its report. Bash is limited to `scripts/verify.sh`,
  `scripts/screenshots.sh` (task 4), the parity validator (task 5), read-only git and `git add`/`git commit`. Denied:
  push, checkout/switch/reset/rebase/merge/worktree/config, `--no-verify`, `supabase`, `security`, `curl`,
  `xcodebuild`, WebFetch and WebSearch.
- Bash runs in the Claude Code sandbox. `verify.sh` and `screenshots.sh` are excluded, because the simulator
  can't run inside it, and they're immutable to workers.
- Workers start with a scrubbed environment (`env -i`, keeping only HOME/PATH/USER/LOGNAME/TMPDIR/LANG/SHELL). No
  `Secrets.xcconfig` exists in any worktree. Preflight fails if any worktree or worker environment contains a
  Supabase key, the prod ref, `GoogleService-Info.plist` or `local.properties`.
- **Dry run in preflight:** a cheap throwaway worker (Haiku, $0.50 cap) in a scratch worktree, with the real
  settings, must (a) be able to edit an allowed file and commit, (b) be denied editing `project.yml`,
  (c) be denied `git push`, (d) report `permissionMode=dontAsk` and zero MCP servers in its init event. The
  scratch worktree is then removed.

### R4 Attribution
Worker settings disable attribution. A committed `scripts/git-hooks/commit-msg` hook (enabled with
`core.hooksPath`) rejects any message containing `Co-Authored-By`, `Generated with`, `Claude Code` or
`noreply@anthropic.com`. Preflight proves the hook rejects such a message. The orchestrator re-checks every
commit on each branch anyway.

### R5 Time and usage limits
| Task | Model | Timeout | Budget cap |
|---|---|---|---|
| 1 database | opus | 180 min | $25 |
| 2 remote rows | opus | 150 min | $15 |
| 3 voice client | sonnet | 150 min | $15 |
| 4 list detail | sonnet | 180 min | $25 |
| 5 parity | opus | 150 min | $20 |

- **Worker deadline:** 05:30. Workers still running then are stopped (TERM, then KILL after 60 s, whole process group).
- **Total deadline:** 06:30. Integration stops starting new merges after that.
- A worker that times out, hits its budget, hits a usage limit or exits non-zero is **incomplete**. The run is
  never resumed automatically. Its worktree and branch are kept as they are, and any uncommitted changes are
  saved as `_state/<n>.uncommitted.patch`.

### R6 Task 4 deterministic screenshots
Prep adds a launch route: `-sampleData -openList <listId>` opens that sample list's detail screen. Task 4 must
provide fixed sample items for `sample-sunday-roast`, matching the Android screenshot: Red wine, Lamb leg,
Double cream, Baby potatoes active; Sourdough completed. `scripts/screenshots.sh` (prep, immutable) sets the status
bar to 9:41, launches with that route in light mode and then dark mode, and saves
`docs/night/screens/list-detail-light.png` and `-dark.png`.

### R7 Task 5 validation and recovery entries
`harness/night/validate_parity.py` (prep, immutable) checks:
- `features.json` parses
- every task has the required fields
- ids are unique and every `depends_on` points to an existing id
- the dependency graph has no cycles
- the task count is between 35 and 60
- every `parity_ids` entry exists in `PARITY.md`
- every PARITY ID is either referenced by a task or marked `excluded`/`done`

It needs no simulator. When integrating, every task among 1–4 that isn't merged gets its recovery entry from
`harness/night/tasks/<n>.json` added to `features.json` with `status: "todo"`, so missing work is never treated as done.

### R8 Preflight proof
Preflight, in a throwaway worktree:
1. Adds a probe source file to each task's source folder and test folder; the probes `import GRDB` and `import Supabase`.
2. Runs one build-for-testing.
3. Proves every probe compiled (its object file exists) and the shared packages link.
4. Removes the worktree.

Preflight also checks: the 18 existing tests pass; Docker and Supabase are not required; there's enough free disk
(at least 20 GB); the Mac is on AC power; the simulators exist; the `claude` CLI is authenticated.

### R9 Immutable acceptance and independent verification
Briefs, metadata, scripts, hooks, settings and `project.yml` are committed before launch and are write-denied to
workers. For each branch, before merging, the orchestrator checks:
- **(a) Scope:** files changed since the prep commit are a subset of the task's owned paths.
- **(b) Commit messages:** no trailer text in any commit message.
- **(c) Clean worktree:** nothing uncommitted.
- **(d) Tests:** its own `verify.sh` run on the branch passes with zero failures, and the task's test folder has
  at least the required number of tests (1: 26, 2: 17, 3: 12, 4: 5).
- **(e) Task 4:** both screenshots exist.
- **(f) Task 5:** the validator passes.

A worker's own claims are never trusted.

### R10 Incomplete work
Anything that fails R9, or is incomplete under R5, is listed in the report with its reason, branch, log path and
patch path. It's kept and never merged into `night/integration`.
