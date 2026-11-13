# Parity spec: Babe, Get This iOS v1 ↔ Android

Source of truth: the Android app on branch `origin/feat/got-this` (PR 39) of `../android/Babe-get-this`.
This file lists every v1 screen, behaviour, user-facing string group and sync/sharing/realtime rule
the iOS app must match. Each item has an ID, a status and the Android file it comes from.

## How to read this

- Line format: `- **AREA-NN** [status] (Android file) rule`. Sub-bullets under an entry belong to it.
- Status:
  - `[todo]`: still to build. Every todo ID is referenced by a task in `harness/features.json`.
  - `[done]`: already on `main`, or delivered by one of tonight's night tasks 1–4 (named in the line).
    If a night task is not merged, its recovery entry (`NIGHT-*`) goes into `features.json`.
  - `[excluded]`: not in iOS v1.
- Path prefixes: `K/` = `app/src/main/java/com/babegetthis/android/`, `T/` = `app/src/test/java/com/babegetthis/android/`,
  `D/` = `docs/`. The other paths are relative to the Android repo root.
- Ported Android tests are the acceptance bar. A behaviour is at parity when the matching Android test cases
  (minus the Got This ones and those of other excluded features) are ported to XCTest and pass.
  Each task's acceptance runs its own test classes with `./scripts/verify.sh <sim> -only-testing:BabeGetThisTests/<Class>`
  and checks `executed` in `build/results/latest.json` against the case count named here, so an empty class can't pass.
- `OPEN DECISION (owner)` marks a point where the sources disagree and the owner has to choose. Don't build it until decided.

## v1 scope decisions (the owner's v1 scope, then decisions taken from the Android docs)

- **In v1:**
  - Offline lists and items, guests with no login wall (`D/technical-decisions/005-require-login.md`, withdrawn).
  - Accounts: email/password, Google, and Sign in with Apple (App Store rule 4.8 when Google is offered).
  - Account-owned lists synced through Supabase (`D/technical-decisions/008-account-owned-lists.md`).
  - Live sharing by 6-character code, with realtime while a list is open.
  - Voice-to-list for signed-in users (`D/product-decisions/002-*.md`, `003-*.md`).
  - Share as text, profile, settings, and telemetry with consent (no App Tracking Transparency prompt, TEL-05).
- **Not in v1 (owner's v1 scope):**
  - Reminders and push notifications, PIN list lock, feature flags and in-app review. Android ships all four;
    the owner ruled them out of iOS v1, so their items below are `[excluded]`.
  - Deep links.
  - Got This: Android TODO.md marks it v2, and CLAUDE.md says iOS v1 acts as a pre-Got-This client that never sends `picked_up_at`.
  - Home widget, Plus tier, camera autofill, pantry, leaving a shared list (none exist on Android either).
  - The Play in-app update flow.
  - The debug-only settings section.
- **Docs vs code conflicts (code wins, except where the owner has decided):**
  - The reset code is 8 digits, as in Android's code. The owner decided this on 2026-11-12, over the handoff's "6-digit" (see AUTH-04).
  - Voice has no review step and does have a mic inside lists (technical decision 002 predates this).
  - A 401 expires the session; it does not log out (`D/auth-network-layer.md` is outdated).
  - Account item catch-up is one RLS-scoped request, not chunks of 50 list ids (the 2026-10-14 spec is outdated).
  - Custom categories exist in the add-item dialog although decision 006 lists them as rejected.

## App shell, configuration, design system

- **APP-01** [done] (app/build.gradle.kts) Three build configs (Dev/Staging/Prod) with their own bundle id, Supabase URL and transcribe API base URL (`AppConfig`), mirroring Android product flavours.
- **APP-02** [done] (app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml) App icons per environment generated from the Android launcher icon.
- **APP-03** [done] (D/screenshots, iOS-only hook) Launch arguments `-sampleData` / `-openList <id>` (non-prod) for screenshots.
- **APP-04** [todo] (app/src/main/res/values/splash.xml, values-night/splash.xml) Launch screen matches the first frame: light background #EDF1F4 with a #607D8B icon, dark background #121212 with a #B0BEC5 icon.
- **APP-05** [todo] (K/BabeGetThisApp.kt) App start: sync trigger registered, auth state restored before the first screen decision. (Android also fetches feature flags here; flags are out of v1, FLAG-01.)
- **UI-01** [done] (K/ui/theme/Color.kt) Colour palette (light and dark, no dynamic colour) and 8 list-accent pairs picked by a stable hash of the list id.
- **UI-02** [done] (K/ui/theme/Theme.kt) Spacing/radii (`AppMetrics`) and button styles (primary 56pt radius 16, outlined, tonal FAB).
- **UI-03** [todo] (K/core/ui/components/BgtTopAppBar.kt) Top app bar: large collapsing variant on home (bold title) and small variant on detail and settings; Light haptic on nav and action taps.
- **UI-04** [todo] (K/core/ui/components/SwipeableCard.kt) Swipeable card: left = delete (red #E53935 at 90%, trash icon), optional right = action (green #43A047, check). Fires once per settled swipe, then snaps back. Radius 14.
- **UI-05** [todo] (K/core/ui/components/SettingsRow.kt) Settings row: 24pt icon, tinted title, optional subtitle, optional trailing control, whole row tappable. Port the 4 SettingsRow cases of SettingsTest.
- **UI-06** [todo] (K/core/ui/haptics/Haptics.kt) Haptics map:
  - Light: nav, top-bar actions, checkbox, swipe-toggle, undo.
  - Medium: FABs, tab switch, swipe-delete.
  - Success: list just completed.
- **UI-07** [todo] (K/navigation/BgtNavGraph.kt) Motion: push to detail slides from the right (300 ms) with the old screen shifting a quarter width left; tab content slides in the direction of travel (280 ms).
- **UI-08** [todo] (TODO.md) Polish pass: no hard-coded user-facing strings (the Android TODO lists 13), VoiceOver labels on every icon button, Dynamic Type everywhere.

## Navigation

- **NAV-01** [todo] (K/navigation/BgtNavGraph.kt) Routes: welcome, login, register, forgot password, lists, list detail (id + name; the title uses the passed name), settings. Port BgtNavGraphTest (8).
- **NAV-02** [todo] (K/MainActivity.kt) Start screen: Welcome when signed out and Welcome not yet answered, otherwise the lists. No login wall.
- **NAV-03** [todo] (K/navigation/BgtNavGraph.kt) Auth stack:
  - Login and Register replace each other; Forgot stacks on Login.
  - Close pops to the lists (or to Welcome if the lists aren't below).
  - Success lands on the lists and drops Welcome.
- **NAV-04** [todo] (K/navigation/BgtNavGraph.kt) Sign-out and account deletion clear the stack to Welcome. A lost session (SessionExpired) stays put.
- **NAV-05** [todo] (K/navigation/BgtNavGraph.kt) Settings is reachable from the lists in every auth state.

## Welcome

- **WEL-01** [done] (K/feature/welcome/ui/WelcomeScreen.kt) Welcome layout: layered circle mark, "Babe, Get This", filled "Sign in" and outlined "Continue as guest".
- **WEL-02** [todo] (K/feature/welcome/ui/WelcomeViewModel.kt) "Continue as guest" persists `welcome_done=true` and replaces Welcome with the lists. "Sign in" pushes Login without persisting, so back returns to Welcome. Port WelcomeViewModelTest (2).
- **WEL-03** [todo] (K/core/onboarding/data/repository/WelcomeRepository.kt) Welcome shows only when Unauthenticated and not answered. `reset()` runs on explicit sign-out and on account deletion. Port WelcomeRepositoryTest (6 minus the 2 upgrade-install cases, X-05).

## Lists overview (home)

- **HOME-01** [done] (K/feature/shoppinglist/ui/components/GreetingSection.kt) Greeting text: before 12 "Good morning", before 17 "Good afternoon", else "Good evening", plus ", FirstName" when a name exists; summary "N list(s) · M item(s) to get" / "nothing to pick up yet" (in-memory `Greeting`).
- **HOME-02** [done] (K/feature/shoppinglist/ui/ShoppingListScreen.kt) Active/Completed tabs, empty state "No lists yet" with "Create your first list", and FAB only when lists exist (in-memory `ListsViewModel`).
- **HOME-03** [todo] (K/feature/shoppinglist/data/local/dao/ShoppingListDao.kt) Lists come from the local DB for the current data owner (guest: `accountId IS NULL AND shareCode IS NULL`; account or expired session: `accountId = owner`). Tombstones are hidden, order is `createdAt DESC`, and the list updates live.
- **HOME-04** [done] (K/feature/shoppinglist/model/ShoppingList.kt) A list is completed when itemCount > 0 and completed == itemCount. Empty lists are Active (`ShoppingListSummary.isCompleted`).
- **HOME-05** [todo] (K/core/util/DateGrouping.kt) Lists within a tab are grouped into Today / Yesterday / Last 7 Days / This Month / Older. The header is a 6pt primary dot plus a bold label. Port DateGroupingTest (13).
- **HOME-06** [done] (K/feature/shoppinglist/ui/components/GreetingSection.kt) Greeting card (title + summary on primaryContainer): `GreetingCard` in `Features/Lists/ListsView.swift`. Remaining work is HOME-18.
- **HOME-18** [todo] (K/feature/shoppinglist/ui/components/GreetingSection.kt) The greeting card shows on the Active tab only, as its first row (today it shows on both tabs), using the signed-in user's name.
- **HOME-07** [done] (K/feature/shoppinglist/ui/components/ShoppingListCard.kt) List card: accent badge with a cart, semibold name, "X/Y items" subtitle and a chevron (`ListCard` in `Features/Lists/ListsView.swift`). Remaining work is HOME-17. (Android's lock icon is out of v1 with PIN lock.)
- **HOME-17** [todo] (K/feature/shoppinglist/ui/components/ShoppingListCard.kt) List card deltas:
  - A check instead of the cart on the Completed tab, and a muted name there.
  - Subtitle "No items yet" when empty and "Y items" on Completed (Active keeps "X/Y items").
- **HOME-08** [todo] (K/feature/shoppinglist/ui/components/TabPillRow.kt) Tab pills: outlined icon when inactive, filled when active; the selected pill is primary with a 200 ms colour animation; Medium haptic. Empty-tab text per tab (TabEmptyState.kt).
- **HOME-09** [todo] (K/feature/shoppinglist/ui/viewModels/ShoppingListViewModel.kt) Swipe left deletes a list (Medium haptic):
  - Guest lists are hard-deleted, account lists soft-deleted.
  - Snackbar "<name> deleted" / "Undo" restores the list and its items on an app-lifetime task.
  - The cache is cleared only after a successful restore. No Undo for a ghost list.
- **HOME-10** [todo] (K/feature/shoppinglist/ui/ShoppingListScreen.kt) Long-press a list → Rename dialog.
- **HOME-11** [todo] (K/feature/shoppinglist/ui/CreateListDialog.kt) Create/Rename dialog:
  - Title "New List" / "Rename List"; field "List name", placeholder "e.g. Weekly Groceries".
  - Max 40 characters; an "n/40" counter appears at the limit.
  - The value is trimmed, and confirm is disabled while blank.
  - Create opens the new list. On failure, a snackbar appears and the dialog stays open.
  - Port CreateListDialogTest (11).
- **HOME-12** [todo] (K/feature/shoppinglist/ui/components/CreateListChooserSheet.kt) The FAB "Create list" is shown on the Active tab only when lists exist. It opens the chooser sheet with "Type" (pencil) and "Voice" (mic, emphasised). Voice when not Authenticated shows the voice sign-in prompt.
- **HOME-13** [todo] (K/feature/shoppinglist/ui/ShoppingListScreen.kt) Top-bar actions: Join, Settings, then the account control. When an account exists (including an expired session) it is an initial avatar that opens the profile sheet; otherwise a "Sign in" pill.
- **HOME-14** [todo] (K/feature/shoppinglist/ui/ShoppingListScreen.kt) Session-expired banner "You've been signed out. Sign in again to keep your lists in sync." with a "Sign in" button.
- **HOME-15** [todo] (K/feature/shoppinglist/ui/ShoppingListScreen.kt) Adoption notice: a one-time dialog after guest lists move into an account. Singular and plural copy; buttons "OK" and "Privacy policy".
- **HOME-16** [todo] (T/feature/shoppinglist/ui/viewModels/ShoppingListViewModelTest.kt) Port the non-telemetry ShoppingListViewModelTest cases (42 total, minus 6 telemetry).

## List detail (items)

- **DET-01** [done] (K/feature/shoppingitems/ui/ShoppingItemsScreen.kt) Night task 4 (`night/4-list-detail`) delivers the list detail screen with an in-memory view model:
  - Progress card; ACTIVE ITEMS grouped by shop then category; COMPLETED.
  - Item card; tick/untick; swipe-delete with Undo.
  - Add-item sheet.
- **DET-02** [todo] (K/feature/shoppingitems/ui/viewModels/ShoppingItemsViewModel.kt) Back the detail view model with the repositories: items are observed live from the DB, and add/edit/tick/delete go through `ShoppingItemRepository`.
- **DET-03** [done] (K/feature/shoppingitems/data/local/dao/ShoppingItemDao.kt) Exact grouping, in `ListDetailViewModel` (night task 4 plus the PR #1 review fixes):
  - Items in DAO order: shop (nil last), category id (nil last), name. Shops A→Z, with the no-shop group last. A "General" header appears only when other shops exist.
  - Categories A→Z case-insensitive, with "Uncategorized" last. Category headers are hidden when a shop's only bucket is uncategorized.
  - Completed is one flat list in DAO order. Items store a category id from `DefaultCategories` and show its name.
- **DET-04** [done] (K/feature/shoppingitems/ui/components/ProgressCard.kt) Progress card: "X of Y picked up", a truncated "NN%" badge and an 8pt bar. The finished state shows a check on primaryContainer (`ProgressCardView`). Remaining work is DET-16.
- **DET-16** [todo] (K/feature/shoppingitems/ui/components/ProgressCard.kt) Progress card celebration (scale spring, check pop, colour pulse), played only on the transition to finished.
- **DET-05** [todo] (K/feature/shoppingitems/ui/components/ShoppingItemCard.kt) Swipe right toggles picked up (green, Light haptic). The checkbox pops (1→1.15→1). A picked-up name is struck through at 45% alpha. Chips show on active items only. Items move between sections with a no-bounce spring.
- **DET-06** [todo] (K/feature/shoppingitems/ui/AddItemDialog.kt) Tapping an item opens the Edit Item dialog. Editing keeps id, listId, createdAt and isPickedUp.
- **DET-07** [done] (K/feature/shoppingitems/ui/AddItemDialog.kt) Dialog limits in `ItemDraft` / `AddItemSheet`:
  - Name max 60. Quantity is required ("Quantity (required)", placeholder "e.g. 2 large, slightly firm").
  - Note max 80, multiline. Shop max 40 (placeholder "e.g. Whole Foods, Costco").
  - Values are trimmed, and blank shop/note become nil. Add sits in the navigation bar, above the keyboard.
  - Remaining work is DET-17.
- **DET-17** [todo] (K/feature/shoppingitems/ui/AddItemDialog.kt) The "n/max" counter that appears when a field reaches its limit (name 60, note 80, shop 40).
- **DET-08** [todo] (K/feature/shoppingitems/ui/AddItemDialog.kt) Category picker:
  - "None" first, then categories A→Z, filtered case-insensitively.
  - When nothing matches: "No categories match "x"".
  - "Other" opens a "New category name" field; the category is created and the item saved with it.
- **DET-09** [done] (K/feature/shoppingitems/ui/components/FirstItemPrompt.kt) First-item prompt on an empty list, instead of the item list and with no progress card: circle mark, "List created!", "Add your first item to get started", "Add first item" (`FirstItemPromptView`).
- **DET-10** [todo] (K/feature/shoppingitems/ui/ShoppingItemsScreen.kt) FABs: a small mic "Add by voice" (always shown; shows the sign-in prompt unless Authenticated) above the extended "+ Add". Medium haptic. The "+ Add" FAB, hidden on an empty list, is already built.
- **DET-11** [todo] (K/feature/shoppingitems/ui/ShoppingItemsScreen.kt) Top-bar actions: "Share live", "Share as text". (Android's lock toggle is out of v1 with PIN lock.)
- **DET-12** [todo] (K/feature/shoppingitems/ui/ShoppingItemsScreen.kt) Leaving an empty, unshared list asks "Delete this empty list?" / "This list has no items, so it will be deleted when you leave." with "Delete list" (destructive) / "Keep editing". Teardown always runs delete-if-empty after any in-flight undo finishes.
- **DET-13** [todo] (K/feature/shoppingitems/ui/viewModels/ShoppingItemsViewModel.kt) The list-completed event fires only on the not-finished → finished transition (including deleting the last unticked item). It plays a Success haptic. (Android also requests an in-app review here; review is out of v1, REV-01.) Port the 5 ListJustCompleted cases of ShoppingItemsViewModelTest.
- **DET-14** [todo] (T/feature/shoppingitems/ui/viewModels/ShoppingItemsViewModelTest.kt) Port the core ShoppingItemsViewModelTest cases. Of the 84: 49 are core, 11 telemetry (TEL-04), and 8 lock, 11 reminder/heads-up and 5 Got This tracker cases are not ported (excluded features). Of the 49 core cases, 5 list-completed (DET-13), 3 share-live (SHARE-05) and 4 realtime (RT-03) cases land with those features, leaving 37 here.
- **DET-15** [todo] (K/feature/shoppingitems/share/ShoppingListShareText.kt) Share as text through the system share sheet. Port ShoppingListShareTextTest (9). Format:
  - `🛒 <name>`, then a blank line.
  - `[ ] <item> (<qty>)` for each unticked item.
  - `(N already picked up)` when some items are ticked.
  - `via Babe, Get This`.
  - When every item is ticked, all items are listed.

## Local data and repositories

- **DATA-01** [done] (K/feature/shoppinglist/data/local/dao/ShoppingListDao.kt) Night task 1 (`night/1-database`) delivers the GRDB schema v1:
  - Tables `shopping_lists`, `shopping_items` (FK, index on listId) and `categories`.
  - Outbox fields `pendingSync`, `onServer`, `accountId`, `deletedAt`. No `pickedUpAt`.
  - The 23 ShoppingListDaoTest cases.
- **DATA-02** [done] (K/core/data/local/DefaultCategories.kt) Default categories, 48 entries with fixed ids, seeded once by migration v1 from a frozen copy (night task 1).
- **DATA-03** [done] (REALTIME_TEST_FINDINGS.md) Existing rows always change with UPDATE or an `INSERT … ON CONFLICT DO UPDATE` upsert, never INSERT OR REPLACE, which would cascade-delete items (night task 1). `ShoppingItemDao.insertItem(s)` keeps Android's upsert semantics (Android: `@Insert(onConflict = REPLACE)`) as a GRDB upsert.
- **DATA-04** [todo] (K/feature/shoppinglist/data/repository/ShoppingListRepository.kt) ShoppingListRepository:
  - createList, createListWithItems (one transaction), renameList, addItemsToList.
  - Blank name → "List name can't be empty."
  - Account lists (`accountId != nil`) are marked `pendingSync` and kick a push; guest lists stay quiet.
  - Port the ShoppingListRepositoryTest cases for these methods (31: owner scoping, create, createWithItems and drafts, addItemsToList, rename, reads, error mapping) and 5 ShoppingListRepositorySharedTest cases (share code, rename and voice-add dirtiness). The 6 lock cases and the reminder onLocalEdit case are not ported.
- **DATA-05** [todo] (K/feature/shoppinglist/data/repository/ShoppingListRepository.kt) List delete and undo:
  - Account lists are soft-deleted (`deletedAt=updatedAt=now`, pending); guest lists are hard-deleted with cascade.
  - Undo restores in place (`deletedAt=nil`, pending, kick), or re-inserts the list with its items for the current owner.
  - Port the 5 delete/restore ShoppingListRepositoryTest cases and the 4 delete/undo ShoppingListRepositorySharedTest cases.
- **DATA-06** [todo] (K/feature/shoppinglist/data/repository/ShoppingListRepository.kt) deleteListIfEmpty. Port DeleteListIfEmptyTest (2), the 10 deleteListIfEmpty cases of ShoppingListRepositoryTest and the 3 of ShoppingListRepositorySharedTest (15).
  - Shared lists are never deleted. Guest lists: atomic delete.
  - Account lists not yet on the server: soft delete.
  - Account lists on the server: require a live session and a successful `catchUp(listId)` first, then soft delete (counting live items only) and kick.
- **DATA-07** [todo] (K/feature/shoppingitems/data/repository/ShoppingItemRepository.kt) ShoppingItemRepository: add, update, delete, restore and toggle picked up.
  - Account lists mark the row pending and kick.
  - Delete is soft or hard depending on the list's owner; restore keeps the original id.
  - Port the non-Got-This ShoppingItemRepositorySharedTest cases (14 minus 3 = 11).
- **DATA-08** [todo] (K/core/data/repository/CategoryRepository.kt) CategoryRepository. Port CategoryDataTest (22).
  - Categories by name A→Z. Defaults can't be deleted.
  - Custom categories are trimmed; blank → "Category name can't be empty."
  - Voice drafts with an unknown category id are saved with a nil category.
- **DATA-09** [todo] (K/feature/gotthis/data/GotThisSync.kt) Before each push, hard-delete any list deleted before it reached the server (`onServer=0 AND deletedAt NOT NULL`); never upload it. This is the non-Got-This home of `deleteNeverSentDeletedLists`.

## Errors

- **ERR-01** [todo] (K/core/error/AppError.kt) AppError cases and default messages. Port AppErrorTest (7).
  - Database: "Something went wrong. Please try again."
  - Network: "No internet connection."
  - Server: "Server error. Please try later."
  - Timeout: "Request timed out. Please try again."
  - Validation: the caller's message.
  - NotFound: "Item not found."
  - Auth: "Authentication failed."
  - Unauthorized: "Session expired. Please log in again."
  - Unknown: "An unexpected error occurred."
- **ERR-02** [todo] (K/core/error/SafeCall.kt) safeCall mapping. Port SafeCallTest (23).
  - SQLite → Database. DNS/connect/TLS → Network ("Cannot reach server." / "Secure connection failed."). Timeouts → Timeout.
  - HTTP 401 → Unauthorized; other 4xx → Auth("Request failed."); 5xx → Server. Anything else → Unknown.
  - Raw messages are never shown, and cancellation is always rethrown.
- **ERR-03** [todo] (K/core/telemetry/data/ErrorReportingPolicy.kt) Only Unknown and Database errors are reported to Crashlytics as non-fatals, from safeCall. Port SafeCallReportingTest (7) and ErrorReportingPolicyTest (8).
- **ERR-04** [todo] (K/core/network/NetworkMonitor.kt) Network monitor: online means a satisfied NWPath (the iOS equivalent of INTERNET+VALIDATED). It gates only auth and voice calls, never the local DB or sync. Port NetworkMonitorTest (6).

## Auth and session

- **AUTH-01** [todo] (K/core/auth/ui/AuthValidation.kt) Email: full match of `[^@\s]+@[^@\s]+\.[^@\s]+`. Empty shows no error; anything else invalid shows "Enter a valid email address". Minimum password length is 6.
- **AUTH-02** [todo] (K/core/auth/ui/LoginViewModel.kt) Login. Port LoginViewModelTest (15).
  - Email and password (show/hide toggle). Valid when the email passes and the password is non-blank.
  - The button shows a spinner while loading; a re-entrant submit is ignored.
  - "Forgot password?", "Continue with Google", a pinned "Don't have an account? Sign up" footer, and a close (X) button.
  - Errors show as a snackbar.
- **AUTH-03** [todo] (K/core/auth/ui/RegisterViewModel.kt) Register. Port RegisterViewModelTest (9).
  - Name, email, password ≥ 6 and confirm, with live "Password must be at least 6 characters" / "Passwords do not match".
  - The name is sent as `user_metadata.name`.
  - No session returned → "Check your email to confirm your account, then sign in."
- **AUTH-04** [todo] (K/core/auth/ui/ForgotPasswordViewModel.kt) Forgot password. Port ForgotPasswordViewModelTest (9).
  - Step 1: email → "Send code". It never reveals whether the account exists.
  - Step 2: an **8-digit** code (digits only, truncated to 8) and a new password ≥ 6.
    - Decided by the owner on 2026-11-12: 8 digits, matching Android's `ForgotPasswordViewModel.kt` `CODE_LENGTH = 8`
      and ForgotPasswordViewModelTest. This replaces the handoff's "6-digit email OTP".
    - The Android repo's local `supabase/config.toml` sets `otp_length = 6` under `[auth.email]`. The iOS local Docker
      stack must set `otp_length = 8`, otherwise Dev and integration tests get 6-digit codes the app rejects.
      Set it in the iOS repo's own Supabase config (planned with the integration-test task), not in the Android repo.
    - Staging and prod Supabase Auth must also use 8. Confirm this in each project's Auth settings before release.
  - Verify the OTP (type recovery), update the password, and end up signed in.
- **AUTH-05** [todo] (K/core/auth/ui/GoogleSignIn.kt) Google sign-in:
  - Generate a raw nonce, send its SHA-256 to Google, then pass the id token and raw nonce to Supabase `signInWithIdToken(provider: google)`.
  - Cancelling is not an error. Offline fails before the sheet opens.
  - Failure → "Google sign-in failed. Please try again."
- **AUTH-06** [todo] (K/core/auth/data/AuthRepository.kt) Sign in with Apple, an iOS addition required by App Store rule 4.8. It uses the same nonce scheme through `signInWithIdToken(provider: apple)`, takes the full name from the first authorisation as `user_metadata.name`, and sits behind the same repository seam as Google.
- **AUTH-07** [todo] (K/core/auth/data/AuthErrorMapper.kt) Auth error copy, checked in order. Port AuthErrorMapperTest (15).
  - id_token / nonce → the Google failure message.
  - "Invalid login" → "Invalid email or password."
  - Already registered → "That email is already registered."
  - "Email not confirmed" → "Please confirm your email before signing in."
  - "expired" → "That code has expired. Request a new one."
  - otp / token → "Invalid code. Check the email and try again."
  - Anything else → "Authentication failed. Please try again."
  - A network error anywhere in the cause chain → Network.
- **AUTH-08** [todo] (K/core/auth/data/SupabaseAuthRepository.kt) Every auth call except logout fails fast with Network when offline.
- **AUTH-09** [todo] (K/core/auth/data/SupabaseAuthRepository.kt) Display name: use `user_metadata.name`, else the fallback (the email local part for login/reset, the typed name for register), else the email's local part.
- **AUTH-10** [todo] (K/core/auth/ui/AuthPromptDialog.kt) Auth prompt dialog: the title and body name the gated feature. "Sign in" → Login; "Create account" → Register. Used for voice ("Sign in to use voice") and for share and join ("Sign in to share").
- **AUTH-11** [todo] (T/core/auth/ui/AuthScreensTest.kt) Port AuthScreensTest (27) as view-model and UI tests where they apply.
- **SESS-01** [todo] (K/core/auth/data/AuthStateManager.kt) Auth states: Loading / Authenticated(userId) / SessionExpired(userId) / Unauthenticated. Port AuthStateManagerTest (28). Restore on launch:
  - No userId → Unauthenticated.
  - A userId without a token → SessionExpired.
  - Both → Authenticated.
- **SESS-02** [todo] (K/core/auth/data/TokenManager.kt) Secure storage in the Keychain: token, userId, name and email. `clearToken` removes only the token; `clear` wipes everything. Port TokenManagerTest (7).
- **SESS-03** [todo] (K/core/auth/data/SessionObserver.kt) Session observer. Port SessionObserverTest (7).
  - Supabase Authenticated → store the rotated token and set the telemetry user id to the UUID.
  - NotAuthenticated → `expireSession()`: drop the token, keep the userId; lists stay editable.
  - Refresh failures (offline) are ignored.
- **SESS-04** [todo] (K/core/auth/data/AuthStateManager.kt) A live session (for server work) means Authenticated only. The data owner is the userId for both Authenticated and SessionExpired.
- **SESS-05** [todo] (K/core/auth/data/SupabaseAuthRepository.kt) Sign-out always succeeds locally:
  - Wipe secure storage → Unauthenticated → Supabase `signOut` (falling back to clearing the session).
  - A `signOuts` event fires only on the transition from an account owner to Unauthenticated.
- **SESS-06** [todo] (K/core/data/network/AuthAuthenticator.kt) Bearer handling on the transcribe API. Port AuthNetworkTest (9).
  - The bearer header is added only when a token exists.
  - A 401 on a request with a bearer → `expireSession()`, with no retry and no refresh.
  - A 401 without one changes nothing.

## Profile

- **PROF-01** [todo] (K/feature/profile/ui/ProfileBottomSheet.kt) Profile sheet, opened from the avatar:
  - Shown only while an account exists; closes on sign-out.
  - Large avatar (initial or person icon).
  - "Name" field with a trailing Save when the trimmed value is non-blank and changed. Messages "Name cannot be empty" / "Name updated".
  - Read-only email, or "No email".
- **PROF-02** [todo] (K/feature/profile/ui/ProfileViewModel.kt) Log out:
  - Push first. If changes are still unsynced, ask "Sign out?" with "Sign out anyway" / "Cancel".
  - Then evict account lists, sign out and reset Welcome.
- **PROF-03** [todo] (K/feature/profile/ui/ProfileViewModel.kt) Delete account. Port ProfileViewModelTest (27).
  - Confirm "Delete account?" with the deletion body and "Delete" / "Cancel".
  - Order: push → RPC `delete_user` → evict → reset Welcome → "Your account has been deleted".
  - A failure keeps every list on the phone.

## Settings

- **SET-01** [todo] (K/feature/settings/ui/SettingsScreen.kt) Settings screen (small app bar, back). Sections in order: Privacy, About. Footer "Version <name> (<build>)". (Android's List lock and Reminders sections are out of v1.)
- **SET-02** [todo] (K/core/ui/Links.kt) About section: "Rate the app" opens the App Store review page (Android opens the Google Play listing). "Privacy policy" opens https://babegetthis.com/privacy-policy.html.
- **SET-03** [todo] (T/feature/settings/ui/SettingsTest.kt) Port the remaining SettingsTest cases: 5 privacy-toggle (consent) cases and the privacy-policy row (6). Of the 75, 32 are Got This, 12 PIN/list lock and 21 reminders (not ported); the 4 SettingsRow cases go with UI-05.

## Categories

- **CAT-01** [todo] (D/technical-decisions/006-category-taxonomy.md) The taxonomy tiebreak rules (product identity beats use, frozen wins, pet wins, baby food beats snacks) apply only to the server categoriser. iOS stores the returned id and shows the category name.

## Voice

- **VOICE-01** [done] (K/core/voice/data/repository/RemoteVoiceRepository.kt) Night task 3 (`night/3-voice-client`) delivers the transcribe client:
  - Multipart `audio` part (`*.m4a`, `audio/mp4`), Bearer, 60 s timeout.
  - DTO mapping, quantity+unit merge, location→shop, error mapping.
  - The 12 RemoteVoiceRepositoryTest cases.
- **VOICE-02** [todo] (T/core/voice/data/repository/ToItemDraftTest.kt) Port ToItemDraftTest (11) into its own class, including the cases night task 3 already covers indirectly.
- **VOICE-03** [todo] (K/core/voice/data/AudioRecorder.kt) Recorder:
  - AVAudioRecorder, AAC in an .m4a file, 16 kHz mono, 30 s max, file `voice-<ms>.m4a` in the caches dir.
  - Plays the `record_start` tone and waits for it to finish before the mic opens.
  - The file is always deleted after transcription or cancel.
- **VOICE-04** [todo] (K/core/voice/ui/viewModels/VoiceCaptureViewModel.kt) Voice view model. Port VoiceCaptureViewModelTest (30).
  - States: Idle, NeedsPermission, Recording, Transcribing, Saving, Done, Failed(message).
  - Start failure: "Couldn't start recording. Is the microphone in use?"
  - Empty result: "Didn't catch any items. Try again?"
  - Stop failure: "Couldn't finish that recording. Try again?"
  - No persist handler: "Something went wrong saving your list."
  - Cancel works from any state, and nothing is saved after it.
- **VOICE-05** [todo] (K/core/voice/ui/VoiceCaptureSheet.kt) Voice sheet (full height):
  - Starts recording immediately if mic permission is granted; otherwise asks.
  - NeedsPermission: "Microphone access is needed to capture your list." + "Allow microphone".
  - Recording: Pebble animation, m:ss timer, "Listening…", "Stop".
  - Transcribing: 5-bar waveform, with text every 2.5 s: "Listening to your list…" → "Sorting your items…" → "Almost there…".
  - Saving: "Saving your list…". Then a success state, and the sheet closes itself.
  - Failed: "Try again" / "Type instead".
  - Dismissing cancels.
- **VOICE-06** [todo] (K/feature/shoppinglist/ui/viewModels/ShoppingListViewModel.kt) No review step: drafts are saved straight away.
  - From the chooser: a new list is created with its items in one transaction, then opened.
  - From the mic inside a list: the items are added to that list.
  - Spoken items need only a name; a missing quantity is saved as empty (`draftsToItems`: `quantity.orEmpty()`). The manual add rule (quantity required) does not apply.
- **VOICE-07** [todo] (T/feature/shoppinglist/ui/viewModels/AutoNameVoiceListTest.kt) Auto-name: the first draft name, trimmed and capped at 40 ("List" if blank), plus " + N more" when there are more items. Port AutoNameVoiceListTest (10).
- **VOICE-08** [todo] (D/product-decisions/003-voice-to-list-requires-authentication.md) Voice opens only when Authenticated. Signed-out and SessionExpired users get the "Sign in to use voice" prompt.

## Sync engine (port `SyncEngine.kt` method by method into a Swift actor)

- **SYNC-01** [done] (K/core/sync/data/mapper/SyncMappers.kt) Night task 2 (`night/2-remote-dto`) delivers:
  - `ListRow`/`ItemRow` Codable with snake_case keys.
  - ISO ↔ epoch-ms helpers and row ↔ local mappers.
  - `picked_up_at` never encoded and ignored on decode.
  - 17 tests.
- **SYNC-02** [todo] (K/core/sync/data/repository/SyncEngine.kt) One serial gate (an actor plus a non-reentrant async lock):
  - It covers push, catchUp, catchUpAccount, claimDeviceLists, evictAccountLists and the sign-out branch.
  - Internal `*Locked` helpers never re-enter it.
  - Every entry point returns a Result.
- **SYNC-03** [todo] (K/core/sync/data/repository/SyncEngine.kt) The server stamps `updated_at` (push sends null). Incoming rows are compared with the local `updatedAt`, which is the server stamp after an apply but the phone clock after a local edit: `markListSynced` / `markItemSynced` only clear `pendingSync`, so the row keeps its phone-clock `updatedAt` until the next apply. Port `shouldSkip` exactly (`incoming == nil` → skip; no local row → apply; else `localDirty || incoming <= localUpdatedAt`). A phone clock ahead of the server can delay a partner's edit until the row changes again; that is Android's behaviour, so keep it.
- **SYNC-04** [todo] (K/core/sync/data/repository/SyncEngine.kt) push(), in order:
  1. Drop never-sent tombstones (DATA-09).
  2. Return if there is no live session.
  3. Pending account lists (tombstones included): `onServer=false` → a plain INSERT one by one, then markOnServer. "Already exists" moves the list into the upsert batch; every other list goes up in one upsert. Then markListSynced.
  4. Pending items in one upsert, then markItemSynced.

  Lists always go before items.

  iOS deliberately closes a race Android has: a list soft-deleted between the drop (step 1) and the pending read (step 3) arrives as a never-sent tombstone. iOS skips it (no INSERT, no markOnServer, its items not sent) and leaves it pending, so the next push's drop deletes it.
- **SYNC-05** [todo] (K/core/sync/data/remote/SupabaseSharedListRemote.kt) A first push is a plain INSERT, because an upsert fails RLS 42501 before the creator-membership trigger has run. A duplicate (`23505` or "duplicate key") returns false.
- **SYNC-06** [todo] (K/feature/shoppinglist/data/local/dao/ShoppingListDao.kt) Clearing the pending flag is guarded:
  - `UPDATE … SET pendingSync=0 WHERE id=? AND updatedAt=?`, so a row edited during the push stays pending.
  - If the item upload fails, item flags stay set and the next kick retries.
- **SYNC-07** [todo] (K/core/sync/data/repository/SyncEngine.kt) catchUp(listId):
  - No session → no-op.
  - `since = syncPoints[listId]`. Fetch the list and its items with `updated_at >= since` (gte, so apply must be idempotent), then apply.
  - Only after the apply succeeds, move the sync point to the max `updated_at`.
- **SYNC-08** [todo] (REALTIME_TEST_FINDINGS.md) fullCatchUp(listId) removes the list's sync point, then catches up. Join uses it so a re-join refreshes the list. iOS deliberately closes a race Android has: the removal runs inside the serial gate, so a catch-up already in flight can't set the old mark again before the full pull reads it.
- **SYNC-09** [todo] (K/core/sync/data/repository/SyncEngine.kt) catchUpAccount(), in order:
  1. Known = the live account list ids.
  2. `fetchAllLists()` with no since filter, because membership changes don't bump `updated_at`.
  3. Split into fresh lists (unknown and live) and the rest; apply the rest.
  4. If discovery returned rows, release unverified claims.
  5. If any lists are known, fetch account items since `syncPoints["account"]` and apply them.
  6. Move the account sync point to the max `updated_at` over those items and the discovered lists.
  7. Then apply each fresh list together with its full item history.
- **SYNC-10** [todo] (K/core/sync/data/repository/SyncEngine.kt) Applying lists:
  - Skip a tombstone for a list the phone never had.
  - A local copy with `accountId=nil` is claimed (accountId=user, onServer=1), even when dirty.
  - shouldSkip when the incoming `updated_at` is nil, the local row is dirty, or incoming ≤ local.
  - Otherwise INSERT if new, UPDATE if it exists. Never REPLACE.
  - iOS deliberately closes a race Android has: the whole apply (lists and items) is one write transaction, so a local edit can't commit between the read, the skip decision and the write and then be overwritten with `pendingSync=0`. It also makes the apply all-or-nothing.
- **SYNC-11** [todo] (K/core/sync/data/repository/SyncEngine.kt) Applying items: skip items whose list is not stored locally (FK guard); skip tombstones for unknown items; apply shouldSkip; otherwise write with `itemDao.insertItem`. Android's is a REPLACE insert (harmless there: items have no children); the iOS `insertItem` is an `INSERT … ON CONFLICT DO UPDATE` upsert, so DATA-03 holds.
- **SYNC-12** [todo] (K/core/sync/data/remote/Paging.kt) Paging. Used by fetchItems, fetchAccountItems and fetchAllLists.
  - Page size 1000, which is PostgREST's max_rows; never set it higher.
  - Keyset paging on `(updated_at, id)`, ascending: next page is `updated_at > s OR (updated_at = s AND id > last)`.
  - Stop at the first short page.
- **SYNC-13** [todo] (K/core/sync/data/repository/SyncEngine.kt) hasUnsyncedChanges(account) is true when pending account lists plus pending items is greater than 0.
- **SYNC-14** [todo] (K/core/sync/data/local/PrefsSyncPointStore.kt) Sync point store: a UserDefaults suite `sync_points` keyed by list id or `"account"`, holding raw ISO strings, with get/set/remove/clear. Port PrefsSyncPointStoreTest (4).
- **SYNC-15** [todo] (K/core/sync/data/remote/SharedListRemote.kt) Remote protocol and its Supabase implementation: insertList, upsertLists, upsertItems, fetchList, fetchItems, fetchAccountItems, fetchAllLists, setShareCode, joinByCode, listChanges.
- **SYNC-16** [todo] (T/core/sync/data/repository/SyncEngineTest.kt) SyncEngineTest, push part, against an in-memory fake remote: the 14 push/outbox cases and the 3 non-Got-This unsynced-count cases (17). SyncEngineTest has 40 cases: 35 non-Got-This, split by method across SYNC-16, SYNC-19 and SYNC-20.
- **SYNC-19** [todo] (T/core/sync/data/repository/SyncEngineTest.kt) SyncEngineTest, catch-up part: the 13 catchUp / apply / fullCatchUp cases.
- **SYNC-20** [todo] (T/core/sync/data/repository/SyncEngineTest.kt) SyncEngineTest, eviction part: the 5 non-Got-This eviction cases (6 minus the purchase-history one).
- **SYNC-17** [todo] (T/core/sync/data/repository/SyncEngineAccountCatchUpTest.kt) Port the SyncEngineAccountCatchUpTest cases minus 3 Got This and 1 list-lock case (14).
- **SYNC-18** [todo] (supabase/migrations/006_got_this.sql) Because iOS v1 never sends `picked_up_at`, migration 006's `items_track_picked_up_at` trigger records iOS ticks as 'legacy'. This is accepted; prove it in an integration test, with no client code.

## Account vs guest lists (decision 008)

- **ACCT-01** [todo] (D/technical-decisions/008-account-owned-lists.md) Ownership columns:
  - `accountId`: nil means a guest list on this device.
  - `onServer` decides INSERT vs upsert.
  - `shareCode != nil` means the list is shared, not that it is synced.
- **ACCT-02** [todo] (K/core/sync/data/repository/SyncEngine.kt) onAuthState:
  - Authenticated → claim, then kick sync.
  - SessionExpired → claim, without syncing.
  - Unauthenticated → finishFirstRun.
  - Loading → nothing.
- **ACCT-03** [todo] (K/feature/shoppinglist/data/local/dao/ShoppingListDao.kt) claimDeviceLists:
  - Drop other accounts' sync points.
  - On the first claim, record ownerless shared list ids as unverified.
  - Then, in one transaction:
    1. Delete other accounts' lists.
    2. Mark guest-list items pending. This must happen before step 3.
    3. Claim guest lists (set accountId and pending) and count them.
    4. On the first claim only, also claim ownerless shared lists.
  - A second run claims nothing.
  - Add the claimed count to the adoption notice.
- **ACCT-04** [todo] (K/core/sync/data/repository/SyncEngine.kt) Two one-off steps:
  - finishFirstRun, once per install: set `account_lists_migrated`. (Android also remembers the locked ids; list lock is out of v1.)
  - releaseUnverifiedClaims, only after a discovery that returned rows: set accountId=nil on (unverified − discovered), then clear the unverified set.
- **ACCT-05** [todo] (K/core/sync/data/local/PrefsListOwnershipStore.kt) Ownership store: a UserDefaults suite `list_ownership` holding `adoption_notice` (Int, observable), `account_lists_migrated` and `unverified_list_ids`. It survives eviction. Port PrefsListOwnershipStoreTest (7 minus the 3 lock cases = 4). (`locked_list_ids` is out of v1 with list lock.)
- **ACCT-06** [todo] (K/core/sync/data/repository/SyncEngine.kt) evictAccountLists(andThen), all inside the lock:
  1. Best-effort push.
  2. Hard-delete every list with `accountId NOT NULL OR shareCode NOT NULL` (cascade). Guest lists stay.
  3. Clear sync points.
  4. Run `andThen`, which is the real logout.
- **ACCT-07** [todo] (D/superpowers/specs/2026-10-14-guest-and-account-lists-design.md) A lost session never evicts: lists stay visible and editable, and sync waits.
- **ACCT-08** [todo] (T/core/sync/data/repository/SyncEngineClaimTest.kt) Port the SyncEngineClaimTest cases minus 4 Got This and 2 list-lock cases (12).

## Sharing

- **SHARE-01** [todo] (K/core/sync/data/repository/ShareRepository.kt) share(listId):
  - Missing list → NotFound("That list no longer exists.").
  - An existing code is returned as is; codes never change.
  - No live session → Auth("Sign in to share lists.").
  - Not on the server → push, then re-read. Still not there → Network("Couldn't share — check your connection.").
  - Otherwise set the code remotely and store the code the server returns, since the first writer wins.
- **SHARE-02** [todo] (K/core/sync/data/repository/ShareRepository.kt) Code format: 6 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. A unique-constraint clash fails the call; a retry generates a new code.
- **SHARE-03** [todo] (K/core/sync/data/repository/ShareRepository.kt) join(code). Port ShareRepositoryTest (13).
  - Calls RPC `join_list_by_code(p_code: trimmed)`, which returns a uuid.
  - An `invalid_code` error → NotFound("That code didn't match any list.").
  - On success, fullCatchUp(listId). A failed pull is returned as an error.
- **SHARE-04** [todo] (K/feature/shoppinglist/ui/JoinListDialog.kt) Join dialog:
  - Signed out → the "Sign in to share" prompt.
  - Signed in → "Join a shared list", field "6-character code", placeholder "ABC234". Input is trimmed, uppercased and capped at 6, with a caps keyboard.
  - "Join" is enabled at exactly 6 characters and not while loading.
  - Errors show inline and are cleared when the dialog reopens.
  - The joined list appears through the live query.
- **SHARE-05** [todo] (K/feature/shoppingitems/ui/ShareCodeDialog.kt) Share live. Port the 3 non-lock share-live cases of ShoppingItemsViewModelTest.
  - Signed out → the sign-in prompt.
  - Otherwise "Share list live": the code in large, letter-spaced type, the hint text, "Copy" (to the clipboard) and "Done".
  - Errors show as a snackbar.
- **SHARE-06** [todo] (D/tradeoff/001-no-attribution-on-shared-list-edits.md) Shared-list edits carry no attribution: who changed what is never shown.

## Realtime

- **RT-01** [todo] (K/core/sync/data/remote/SupabaseSharedListRemote.kt) One channel `list-<listId>`:
  - Postgres changes on `public.lists` (`id=eq.<id>`) and `public.items` (`list_id=eq.<id>`), merged into one signal.
  - Every SUBSCRIBED status (the first join and every re-join) also signals.
  - The channel is removed when collection ends.
  - iOS: each subscription gets its own topic `list-<listId>-<uuid>`, because supabase-swift reuses a registered topic (Android's `channel(...)` builds a new channel each time).
- **RT-02** [todo] (REALTIME_TEST_FINDINGS.md) Realtime carries no data: every signal → `catchUp(listId)`. Measured median latency is about 0.7–0.9 s.
- **RT-03** [todo] (K/feature/shoppingitems/ui/viewModels/ShoppingItemsViewModel.kt) On the detail screen, keyed on whether the list is shared:
  - Shared: catch up once, then subscribe.
  - Unshared account list: catch up once, with no socket.
  - Guest list: nothing.
  - Torn down when the list is unshared or the screen closes. The lists overview never subscribes.
  - Port the 4 realtime cases of ShoppingItemsViewModelTest.

## Sync triggers

- **TRIG-01** [todo] (K/core/sync/SyncTrigger.kt) kick() = push() then catchUpAccount(), on a detached task. Results are discarded. No debounce and no timer; duplicate kicks are harmless. Port SyncTriggerTest (7).
- **TRIG-02** [todo] (K/core/sync/SyncTrigger.kt) A kick fires on:
  - an auth transition where onAuthState returns true (this includes launch while signed in);
  - network becoming available, including at registration;
  - the app becoming active (scenePhase).
- **TRIG-03** [todo] (K/core/sync/SyncKicker.kt) `pushSoon()` is push only and fire-and-forget. Repositories call it after local writes to account lists.

## Server (migrations 001–006; read-only facts the client relies on)

- **SRV-01** [todo] (supabase/migrations/001_realtime_list_sharing.sql) Tables:
  - `lists`: id, name, share_code (unique, nullable), created_by (nullable, ON DELETE SET NULL), created_at, updated_at, deleted_at.
  - `items`: id, list_id (cascade), name, quantity (default '1'), is_picked_up, category_id, shop, note, updated_at, deleted_at.
  - `list_members`: list_id, user_id, joined_at.
- **SRV-02** [todo] (supabase/migrations/003_account_lists.sql) Triggers:
  - `set_updated_at` uses the server clock.
  - `protect_list_immutables` keeps share_code and created_at write-once (coalesce), and keeps created_by unless the new value is null.
  - `lists_add_creator` adds the creator's membership after insert.
- **SRV-03** [todo] (supabase/migrations/001_realtime_list_sharing.sql) RLS:
  - SELECT and UPDATE on `lists`/`items` require `is_list_member`.
  - A list can be inserted only with `created_by = auth.uid()`; items only by a member.
  - No DELETE policies (soft delete only) and no direct `list_members` insert.
- **SRV-04** [todo] (supabase/migrations/004_delete_user_purges_solo_lists.sql) `delete_user()` removes the caller's solo lists (items cascade), then the auth user. Shared lists stay, with `created_by` set to null.
- **SRV-05** [todo] (supabase/migrations/005_items_updated_at_index.sql) Index `items(updated_at)` backs the account-wide item query, which relies on RLS rather than a list filter.
- **SRV-06** [todo] (supabase/tests/database/000_baseline.test.sql) Integration tests against the local Docker Supabase with migrations 001–006: first INSERT, upsert, the join RPC, realtime catch-up and RLS denial. Never against production.
  - They live in their own test target, run by a separate test plan, so the default `verify.sh` run never needs Docker.
  - They fail, not skip, when 127.0.0.1:54321 is unreachable.

## Telemetry (Firebase is in the iOS stack)

- **TEL-01** [todo] (D/technical-decisions/007-telemetry.md) AnalyticsRepository and CrashReporter protocols with Firebase implementations. Staging and Prod use separate Firebase projects; Dev sends nothing.
- **TEL-02** [todo] (K/core/telemetry/TelemetryConsent.kt) Consent is two independent toggles, "Usage analytics" and "Crash reports". Both are on by default and re-applied at launch. Identity is the Supabase user UUID only. Port TelemetryConsentTest (7).
- **TEL-03** [todo] (K/core/telemetry/data/AnalyticsEventMapper.kt) The non-Got-This events, with params limited to enums, buckets and ids (never item names, emails or codes):
  - `screen_view`.
  - Voice: sheet opened, recording started/failed/cancelled, transcription completed/failed, items saved.
  - Sharing: share_code_created/shared, join attempted/succeeded/failed, shared_list_first_edit.
  - Activation: welcome_choice, account_registered/logged_in, first_item_added, first_list_completed.
  - Habit: item_added, item_checked_off, list_completed, category_auto_assigned/corrected.
  - (Android's reminder_posted / reminder_tapped are out of v1 with reminders.)
  - Port AnalyticsEventMapperTest (24 minus 4 Got This and 2 reminder = 18), BucketsTest (10 minus 2 reminder = 8), FailureReasonsTest (2), TelemetryMarkersTest (6) and TelemetryContextTest (8).
- **TEL-04** [todo] (K/core/telemetry/model/AnalyticsEvent.kt) Wire the events into the view models: the 6 telemetry cases of ShoppingListViewModelTest and the 11 of ShoppingItemsViewModelTest.
- **TEL-05** [todo] (D/technical-decisions/007-telemetry.md) No App Tracking Transparency prompt and no IDFA collection: Firebase Analytics is added without ad-id support, so AdSupport is not linked through Firebase, and there is no `NSUserTrackingUsageDescription`.

## Feature flags, review (out of v1: owner's v1 scope)

- **FLAG-01** [excluded] (K/core/featureflags/FeatureFlagCache.kt) Feature flags. Port FeatureFlagCacheTest (5).
  - `feature_flags(key, enabled)` is fetched once per cold start into an in-memory cache and never blocks launch.
  - `isEnabled` defaults to false.
  - `isKnownOff` is true only when the flags loaded and the key isn't true.
- **REV-01** [excluded] (K/core/review/InAppReview.kt) A review is requested (`RequestReviewAction`) on every list-just-completed transition. There is no pre-prompt and no local throttle; the OS quota decides. Errors are swallowed.

## PIN list lock (out of v1: owner's v1 scope)

- **PIN-01** [excluded] (K/core/pin/data/PinCrypto.kt) One 4-digit PIN per device, stored in the Keychain. Port PinCryptoTest (26) and the PinStoreTest cases.
  - It survives logout and never syncs.
  - Hashing: PBKDF2-HMAC-SHA256, 120k iterations, 256-bit key, 16-byte salt.
  - Compared in constant time.
- **PIN-02** [excluded] (K/core/pin/data/PinRepository.kt) Recovery code and PIN rules. Port PinRepositoryTest (28).
  - Recovery code: 10 Crockford base32 characters, shown once.
  - Input is normalised (O→0, I/L→1, other characters dropped).
  - Using the code resets the PIN and issues a new code. The code can be regenerated.
  - Setup refuses if a PIN exists; change and remove need the current PIN.
- **PIN-03** [excluded] (K/core/pin/data/PinThrottle.kt) Throttle. Port PinThrottleTest (12).
  - Every 5th consecutive failure locks out for 30 s → 2 m → 10 m → 1 h (the cap).
  - The lockout uses the larger of wall-clock and monotonic time.
  - Messages: "Wrong PIN. N attempts left." / "Too many attempts. Try again in X."
- **PIN-04** [excluded] (K/core/pin/ui/PinDialogs.kt) PIN dialogs: create, confirm, unlock, delete, share, verify current, new PIN, recovery show and recovery entry. Port PinDialogsTest (22) and PinPromptViewModelTest (16).
- **PIN-05** [excluded] (K/feature/shoppingitems/ui/ShoppingItemsScreen.kt) Locked lists:
  - Opening, swipe-deleting and sharing need the PIN. Cancelling a delete shows "Nothing was deleted".
  - Content is hidden until unlocked, and the list re-locks when the app goes to the background.
  - App-switcher snapshots are obscured while locked (the FLAG_SECURE equivalent).
  - Locking with no PIN set goes through setup.
  - Locked ids are kept in the ownership store.
- **PIN-06** [excluded] (K/feature/settings/ui/SettingsScreen.kt) Settings "List lock" section: Set up / Change / Remove (warns that all lists unlock) / Regenerate recovery / Forgot, plus the device-only caveat.

## Shopping reminders (out of v1: owner's v1 scope, no reminders or push)

- **REM-01** [excluded] (K/core/reminder/ReminderScheduler.kt) Arming. Port ReminderSchedulerTest.
  - A list is eligible when at least 1 item was ticked on this phone and at least 1 item is unticked.
  - The reminder fires 3 h after the last local activity. Partner changes neither arm nor reset it.
  - One pending reminder app-wide (the newest eligible list), one per session, never retried, silent when in doubt.
  - Kill switch: feature flag `shopping_reminders`.
- **REM-02** [excluded] (K/core/reminder/ReminderNotifier.kt) Local notification. Port ReminderNotifierTest and ReminderContentReaderTest.
  - Title "Forget something on <list>?".
  - Body names up to 2 unticked items plus "N more". Locked lists show the count only.
  - A fixed identifier, so a new notification replaces the old one.
- **REM-03** [excluded] (K/core/reminder/ReminderIntentParser.kt) Tapping the notification opens that list above the lists overview. Port ReminderIntentParserTest.
- **REM-04** [excluded] (K/core/reminder/ui/ReminderPermissionSheet.kt) In-context permission:
  - On the first partly-shopped tick, a "Forget something?" sheet ("Remind me" / "Not now") appears before the system prompt.
  - Not now, dismiss or deny snoozes the offer for 14 days.
  - Never shown when permission is already granted, the toggle is off, the offer is snoozed, or permission is permanently denied.
- **REM-05** [excluded] (K/core/reminder/ui/NotificationSettings.kt) The Settings reminders switch reflects the preference (default on) AND the OS permission. When permission is denied, the row opens system settings.

## User-facing strings (app/src/main/res/values/strings.xml: 185 strings + 10 plurals, ported to a String Catalog with the same keys)

- **STR-01** [todo] (app/src/main/res/values/strings.xml) Common: app_name, cancel, create, undo, add, save, the done key, account.
- **STR-02** [todo] (app/src/main/res/values/strings.xml) Welcome and adoption: welcome_sign_in, welcome_continue_as_guest, auth_welcome, adoption_notice (plural), adoption_notice_ok, adoption_notice_privacy.
- **STR-03** [todo] (app/src/main/res/values/strings.xml) Home: shopping_list_empty_title/subtitle/cta, shopping_list_create, shopping_list_items_count/progress (plurals on the total), greeting_lists, greeting_items_to_get, greeting_nothing_to_get, greeting_summary, shopping_list_all_completed, shopping_list_no_completed, tab_active, tab_completed, snackbar_deleted, session_expired_banner, session_expired_sign_in.
- **STR-04** [todo] (app/src/main/res/values/strings.xml) Create, rename and join: shopping_list_name_hint, shopping_list_create_title, create_list_type, create_list_voice, shopping_list_edit_title, join_list_title, join_list_hint, join_list_button, join_list_action.
- **STR-05** [todo] (app/src/main/res/values/strings.xml) List detail: shopping_items_active, shopping_items_completed, shopping_items_count (plural), shopping_items_list_created, shopping_items_add_first(_button), leave_empty_list_title/body/confirm/stay.
- **STR-06** [todo] (app/src/main/res/values/strings.xml) Add/edit item: shopping_items_add_title, shopping_items_edit_title, shopping_items_name_hint, shopping_items_quantity_hint/placeholder, shopping_items_category(_placeholder), shopping_items_category_no_match, shopping_items_note(_placeholder), shopping_items_shop(_placeholder), shopping_items_new_category, category_none, category_other.
- **STR-07** [todo] (app/src/main/res/values/strings.xml) Share: share_auth_title, share_auth_body, share_live_title, share_live_hint, share_live_copy, share_live_action, share_as_text.
- **STR-08** [todo] (app/src/main/res/values/strings.xml) Voice: voice_add, voice_auth_title, voice_auth_body, plus the sheet copy hard-coded in VoiceCaptureSheet.kt.
- **STR-09** [todo] (app/src/main/res/values/strings.xml) Auth: auth_login_subtitle, auth_register_subtitle, auth_email, auth_password, auth_confirm_password, auth_name, auth_login, auth_register, auth_forgot_password, auth_reset_password, auth_forgot_subtitle, auth_code_sent, auth_code, auth_new_password, auth_send_code, auth_no_account, auth_has_account, auth_sign_up, auth_sign_in, auth_continue_with_google, plus "Continue with Apple" for iOS.
- **STR-10** [todo] (app/src/main/res/values/strings.xml) Profile: profile_name, profile_no_email, profile_logout, sign_out_unsynced_title/body/confirm, delete_account_body.
- **STR-11** [todo] (app/src/main/res/values/strings.xml) Settings, privacy and about: settings, settings_title, settings_privacy_section, settings_analytics_title/subtitle, settings_crash_title/subtitle, settings_about_section, settings_privacy_policy_title/subtitle, settings_rate_title/subtitle (iOS says App Store instead of Google Play).
- **STR-12** [excluded] (app/src/main/res/values/strings.xml) PIN and lock: settings_pin_*, pin_* (pin_wrong plural, pin_locked_out), recovery_*, lock_list, unlock_list, lock_locked, lock_delete_cancelled, lock_remove_pin_warning (plural).
- **STR-13** [excluded] (app/src/main/res/values/strings.xml) Reminders: reminder_title, reminder_body_one/two/more, reminder_body_locked (plural), reminder_prompt_*, settings_reminders_*. reminder_channel_name is Android-only.
- **STR-14** [todo] (K/core/error/AppError.kt) Error copy that lives in Kotlin (AppError, AuthErrorMapper, the repositories, the voice view model) also goes into the catalog.
- **STR-15** [excluded] (app/src/main/res/values/strings.xml) Got This strings: settings_got_this_*, got_this_*.

## Excluded from iOS v1

- **GOT-01** [excluded] (K/feature/gotthis/ui/BoughtHintLine.kt) "Bought today / yesterday / N days ago" hint line, with Remove and Don't remind me (a 60-day mute).
- **GOT-02** [excluded] (K/feature/gotthis/ui/UsualsRow.kt) "Usually bought around now" usuals chip row and the weekly heads-up CTA.
- **GOT-03** [excluded] (K/feature/gotthis/reminder/RunningLowScheduler.kt) Weekly running-low notification.
- **GOT-04** [excluded] (supabase/migrations/006_got_this.sql) Purchase history, the tick outbox, `picked_up_at`, and the RPCs `record_ticks`, `upload_own_purchases`, `clear_purchase_history` and `claim_running_low_week`.
- **GOT-05** [excluded] (K/feature/settings/ui/SettingsScreen.kt) The Settings "Got This" section (hints, running low, clear history) and the `got_this` / `got_this_holdout` flags.
- **GOT-06** [excluded] (K/feature/gotthis/data/GotThisSync.kt) The Got This hooks in SyncEngine (push, pull, prepareClaim, claimGuestHistory, evict, unsyncedCount) and the Got This cases in the sync tests.
- **X-01** [excluded] (K/core/update/InAppUpdateManager.kt) Play in-app update (immediate/flexible, "Restart" snackbar). iOS has no equivalent API.
- **X-02** [excluded] (D/product-decisions/002-voice-to-list-replaces-widget-for-v1.md) Home-screen widget, persistent shopping notification, share-intent receiver, app shortcuts.
- **X-03** [excluded] (TODO.md) Plus paid tier, camera/gallery autofill, pantry, leaving a shared list (`left_at`).
- **X-04** [excluded] (K/feature/settings/ui/SettingsScreen.kt) The debug-only settings section.
- **X-05** [excluded] (K/core/onboarding/data/repository/WelcomeRepository.kt) Skipping Welcome on upgrade installs. iOS has no earlier install base.
- **X-06** [excluded] (baselineprofile/README.md) Baseline profiles and Android startup benchmarks.
