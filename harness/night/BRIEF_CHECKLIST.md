# Writing briefs: checklist

Check each new `harness/night/briefs/<task>.md` and its `nights/<id>.json` entry against this list before a run.
It comes from the reviews of runs 2026-11-13e and 2026-11-13f (PR #7), 2026-11-14a and 2026-11-14b (PR #9), 2026-11-14c and 2026-11-14d (PR #11), and 2026-11-14e and 2026-11-14f (PR #13). Briefs from earlier runs are records and stay as they were.

## Waves and ownership
- `integrate.py`'s scope check passes any file under a task's owned prefix. It can't stop two workers in one wave from editing the same lines.
- If two tasks in one wave own the same directory, each brief names the shared files and the exact hook points it may touch, and keeps those edits small and local.
  Better: land a small scaffold commit on the base first (init parameters, call sites) and let each task own only its new files.
  Otherwise, put the tasks in separate waves and chain them with `requires`.
- A read-only dependency on a file that another task in the same wave owns is a risk. Do one of these:
  - In the owning task's brief, list the symbols that are frozen for this wave.
  - Move the shared type to a folder neither task owns.
  - Chain the tasks.
- When tasks in one wave share a directory, each owns the specific files it creates or edits, not the directory.
  An owned directory prefix lets the scope check accept edits to the other task's files in it.
- Don't ask a worker to move, delete or replace files outside its owned paths, or to use a command the worker
  settings deny (`make_settings.py` denies `rm`, `mv` and `chmod`). Either own those paths and allow `git rm`,
  or say "don't move, don't duplicate; list the overlap" and leave the clean-up to an orchestrator step.
- Resolve every "don't touch X" against the rules that need X. When a rule can only be met by editing X (for example
  NAV-03 from a list's screen needs a hook in `Features/ListDetail/`), name that case and decide it in the brief:
  own the hook point, or record the deviation in the PARITY row.
- Cross-check the briefs of a wave against each other: what each says the others will change in a shared file must match what those briefs allow.
- Wiring a frozen interface to its UI is a named task's job, and that task owns both ends: the screen that takes the
  object and the file that builds the screen. In 2026-11-14e/f F42 froze `TelemetryConsentStore` and was told to keep
  `SettingsView()`'s initialiser, F44 built `TelemetryConsent` but owned neither `Features/Settings/` nor
  `ListsView.swift`, and no task connected them: the toggles only took effect at the next launch (fixed in PR #14).
- A brief that asks for a PARITY note owns `docs/PARITY.md` in the night config, limited to the rows it names; or the
  note goes into the PR that adds the brief, before the run. F42 was asked to record the SET-02 rate-row deviation
  without owning the file, so the worker listed it as Blocked and the deviation merged unrecorded.
- A case that depends on an API another task adds in the same wave is ported by the task that adds the API, or the two tasks are chained.
  Don't leave a fallback port that tests something else in its place.
- A merge resolved by hand re-runs that task's acceptance commands on the merged result, not only the full suite.

## Dependencies
- A task's `requires` in the night config matches its `depends_on` in `harness/features.json`.
  When a brief builds on another task's work, add that task to both.
- In a chained wave, the `worker_deadline` leaves at least the longest task `timeout_min` after the previous wave's `total_deadline`.

## Port from and acceptance
- "Port from" covers every behaviour the brief asks for. List the Android source files and the Android test cases by name or line range.
  For example, `ShoppingItemsViewModelTest.kt`: the 5 `leavingDeletesList` cases and the 3 `onCleared` cases.
- "Port from" lists every Android source a behaviour lives in, down to the block: for F24 that was `WelcomeScreen.kt`,
  `AuthPromptDialog.kt`, `ProfileBottomSheet.kt`, and in `ShoppingListScreen.kt` the `AccountAction`, `SessionExpiredBanner`
  and `LaunchedEffect(hasAccount)` blocks.
- "Port from" includes the code a ported test exercises and where the feature is wired, not only the feature's own
  folder. F44 left out `core/error/SafeCall.kt` and `core/error/ErrorReporter.kt` (behind `SafeCallReportingTest`),
  `core/auth/data/SessionObserver.kt` (`telemetryContext.onUserChanged`, lines 49 and 65), `BabeGetThisApp.kt:77`
  (`onAppStart()`), `MainActivity.kt:97` (`onScreen`) and `feature/settings/ui/SettingsViewModel.kt:69` (consent applied on a toggle).
- "Port from" names the data source behind each behaviour and where the screen is hosted. F37 left out
  `core/auth/data/AuthStateManager.kt` (`dataOwnerId()` line 37, the `userName`/`userEmail` flows lines 67 and 73),
  `core/auth/data/SupabaseAuthRepository.kt` (`deleteAccount`, line 118, which is what lands deletion on Welcome) and
  `feature/shoppinglist/ui/ShoppingListScreen.kt` (the `ProfileBottomSheet(` block, line 522, which forwards its toasts).
- Check every case count and split against the Android test file, by line. BgtNavGraphTest has 4 reminder cases
  (60, 70, 81, 92), the name round-trip (103) and 3 create-list cases (112, 122, 129), not "5 reminder cases".
  For a case that doesn't carry over as is, say what the iOS port must assert instead, or drop it as not applicable.
- Each behaviour in the brief, copy variants included (for example singular and plural strings), has an acceptance command in `features.json`. Usually that is `-only-testing:BabeGetThisTests/<Class>` with an `executed <` threshold.
  UI-side behaviour (dialogs, teardown) needs its own test class too, not only the repository's.
- Every behaviour the brief describes gets an acceptance test class, with the cases it must have named. F24's HOME-13,
  HOME-14 and NAV-05 had none (now `AccountControlTests`), so "signing out closes the profile sheet and it stays
  closed on the next sign-in" was never required. When the brief names test methods, run the whole class too
  (F23: `IdTokenSignInTests`), so the error mapping, offline and not-configured cases are gated.
- Say how to port cases that assert on rendered UI while there is no UI test target (`project.yml` has only
  `bundle.unit-test`): the view must be built from the shared field and layout lists the test checks, and its taps
  routed through a type the test drives. A test that compares a constant with a literal can't fail, so it doesn't
  count toward an `executed <` gate; otherwise mark the case "adapted" in the PARITY row and lower the gate.
- Gate whole classes, never only single methods, and list in the brief what each class must cover. F42 gated
  `testSectionsArePrivacyThenAbout` (a constant against a literal) and `testVersionFooterFormat` (a string
  interpolation), so toggles on by default, persistence under Android's keys, the hidden rate row and the privacy URL
  were gated by nothing. `features.json` now gates `SettingsViewModelTests` as a whole.
- A sheet's UI behaviour gets its own acceptance class, and live adapters are tested against fakes of the layer below
  them, not the view model's fakes. F37 gated only `ProfileViewModelTests` on fakes that call back synchronously:
  Save visibility, the avatar initial or person icon, "Your account has been deleted" outliving the sheet, sign-out and
  deletion landing on Welcome while SessionExpired stays, and the account switch through the real `AuthStateManager`
  had no class. Name them in the brief (for example `ProfileSheetTests`, `ProfileNavigationTests`, `ProfileAdapterTests`).

## Facts the brief must state, not paraphrase
- Quote parity rows and Android behaviour as written; don't add behaviour. F24's "or of the email if there's no name"
  was in neither HOME-13 nor Android `AccountAction` (name initial, else a person glyph). A deliberate iOS choice goes
  into the PARITY row first, as a deviation.
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
