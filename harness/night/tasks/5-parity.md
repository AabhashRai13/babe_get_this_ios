# Task 5: Parity spec and task list
Branch `night/5-parity`. No simulator (docs only).

## Owned paths
- `docs/PARITY.md`
- `harness/features.json`
- `docs/night/5-parity.md`

## Read (Android, `origin/feat/got-this`)
`docs/technical-decisions/*`, `docs/product-decisions/*`, `docs/superpowers/specs/*`, `supabase/migrations/001`–`006`,
`REALTIME_TEST_FINDINGS.md`, screens, `res/values/strings.xml`, and the sync code (`core/sync/`, ShareRepository, Paging, SyncTrigger).
Also read the iOS handoff decisions in `CLAUDE.md` and the spec. Read what already exists on this branch (`BabeGetThis/`)
and the briefs for tasks 1–4 in `harness/night/tasks/`: those deliverables are covered elsewhere and must be excluded.

## Acceptance (immutable)
- `PARITY.md`: every v1 screen, behaviour, user-facing string and sync/sharing/realtime rule, each with an ID in the form
  `AREA-NN` (for example `SYNC-07`) on its own line starting with `- **ID**` and its Android file reference.
  Out-of-v1 features are listed as excluded: their IDs appear on a line containing `excluded`.
  Already-built items appear on a line containing `done`.
- `features.json`: a JSON object `{"tasks": [...]}` with about 45 tasks (35–60) in dependency order. Each task has `id`, `title`,
  `parity_ids` (list of PARITY IDs), `depends_on` (list of task ids), `acceptance` (list of shell commands) and
  `status: "todo"`. It excludes what already exists on `main` and what tasks 1–4 deliver.
- Docs only. No Swift changes.
- `python3 harness/night/validate_parity.py` passes (run it; it is the only check).
