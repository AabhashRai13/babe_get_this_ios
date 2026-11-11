# Night task 5: parity spec and task list

Branch `night/5-parity`. Docs only; no Swift changes.

## Summary
- `docs/PARITY.md` has 185 parity IDs: 158 todo, and 27 either done or excluded.
  - It was built by reading `origin/feat/got-this`: the technical and product decisions, the specs, migrations 001–006,
    REALTIME_TEST_FINDINGS.md, strings.xml (185 strings + 10 plurals), every screen, the view models,
    the sync code (SyncEngine, ShareRepository, Paging, SyncTrigger/Kicker, stores, remote) and the test-case counts.
  - Every ID line has the Android file it comes from.
  - It records the v1 scope decisions and the places where the Android docs and code disagree (the code wins).
- `harness/features.json` has 51 tasks (F01–F51) in dependency order.
  - Each task has `parity_ids`, `depends_on`, shell acceptance commands (a test-class grep plus `./scripts/verify.sh`) and `status: "todo"`.
  - It leaves out what is already on `main` (config/environments, design system, Welcome layout, the in-memory lists overview, the launch route).
  - It also leaves out what night tasks 1–4 deliver (GRDB schema/DAO/categories, rows/mappers, transcribe client, in-memory list detail). These are marked `[done]` with the night task named.

## Acceptance checklist
- [done] PARITY.md: every v1 screen, behaviour, user-facing string group and sync/sharing/realtime rule has an `AREA-NN` ID on a `- **ID**` line with its Android file reference. Out-of-v1 items are on `excluded` lines; already-built items are on `done` lines.
- [done] features.json: `{"tasks": [...]}` with 51 tasks (within 35–60) in dependency order. Each task has the required fields and `status: "todo"`, and none of them redo main or tasks 1–4.
- [done] Docs only; no Swift changes.
- [done] `python3 harness/night/validate_parity.py` → `PARITY VALID: 185 parity ids, 51 tasks (0 recovery)`.

Verify: no simulator for this task, so `./scripts/verify.sh` was not run. The only check is the validator, quoted above.

## Decisions taken from the docs (for the owner's morning review)
- **In v1:** PIN list lock, shopping reminders, telemetry, feature flags and in-app review. Android shipped them and is the spec.
- **Excluded:**
  - Got This (TODO.md says v2; CLAUDE.md says iOS v1 is a pre-Got-This client).
  - Play in-app update.
  - The widget, Plus tier, camera, pantry and leaving a shared list.
- **Sign in with Apple** is added (AUTH-06): App Store rule 4.8 requires it when Google sign-in is offered. This is an iOS-only addition with no Android counterpart.
- If the owner wants a smaller v1, the PIN tasks (F46–F48) and reminders (F49) can be cut without touching anything else; they sit at the end of the dependency graph.

## Blocked
- Nothing.

## Follow-ups
- **Acceptance commands are placeholders.** They grep for test class or function names the future tasks should create, and use `./scripts/verify.sh "iPhone 18 Pro"`. Adjust the simulator name per run.
- **SRV-06 / F38** needs a way to run integration tests against the local Docker Supabase. Today verify.sh has no Supabase step.
- **Android docs and code disagree:**
  - The reset code is 8 digits, but an AuthRepository comment says 6.
  - Custom categories exist in the add-item dialog although decision 006 lists them as rejected.
  - The voice 30 s cap silently stops the recorder.

  The owner may want these fixed upstream.
