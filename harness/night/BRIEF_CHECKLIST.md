# Writing briefs: checklist

Check each new `harness/night/briefs/<task>.md` and its `nights/<id>.json` entry against this list before a run.
It comes from the review of runs 2026-11-13e and 2026-11-13f (PR #7). Briefs from earlier runs are records and stay as they were.

## Waves and ownership
- `integrate.py`'s scope check passes any file under a task's owned prefix. It can't stop two workers in one wave from editing the same lines.
- If two tasks in one wave own the same directory, each brief names the shared files and the exact hook points it may touch, and keeps those edits small and local.
  Better: land a small scaffold commit on the base first (init parameters, call sites) and let each task own only its new files.
  Otherwise, put the tasks in separate waves and chain them with `requires`.
- A read-only dependency on a file that another task in the same wave owns is a risk. Do one of these:
  - In the owning task's brief, list the symbols that are frozen for this wave.
  - Move the shared type to a folder neither task owns.
  - Chain the tasks.
- A merge resolved by hand re-runs that task's acceptance commands on the merged result, not only the full suite.

## Dependencies
- A task's `requires` in the night config matches its `depends_on` in `harness/features.json`.
  When a brief builds on another task's work, add that task to both.

## Port from and acceptance
- "Port from" covers every behaviour the brief asks for. List the Android source files and the Android test cases by name or line range.
  For example, `ShoppingItemsViewModelTest.kt`: the 5 `leavingDeletesList` cases and the 3 `onCleared` cases.
- Each behaviour has an acceptance command in `features.json`. Usually that is `-only-testing:BabeGetThisTests/<Class>` with an `executed <` threshold.
  UI-side behaviour (dialogs, teardown) needs its own test class too, not only the repository's.

## Facts the brief must state, not paraphrase
- Strings: no String Catalog exists yet, so don't require one. Strings stay SwiftUI literals with Android's exact wording until a catalog task (STR-xx) exists.
  Leave STR parity ids out of a task that can't meet them, or give the brief the catalog path to own.
- Outbox and tombstone rules: quote `docs/PARITY.md` (DATA-06 and the related SYNC entries) word for word.
  For deleteListIfEmpty there are four branches:
  - shared lists are kept;
  - guest lists are hard-deleted;
  - an account list not on the server is tombstoned, and a push is kicked;
  - an account list on the server is tombstoned only after a live session and a successful `catchUp(listId)`.
- Wiring: if a behaviour needs `BabeGetThis/App/AppContainer.swift` (or another unowned file), either own that file, or say the wiring is deferred and name the task that does it.
- Data sources: name where the data comes from. For example, "the picker lists `CategoryRepository.allCategories()`, live", not just "categories A→Z".
