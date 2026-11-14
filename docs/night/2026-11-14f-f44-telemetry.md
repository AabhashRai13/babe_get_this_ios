# F44 night report: telemetry (2026-11-14f)

## Summary
Ported Android `core/telemetry` to `BabeGetThis/Core/Telemetry/`:
- `AnalyticsEvent` covers the TEL-03 catalog without the reminder and Got This events. It reuses the existing
  `WelcomeChoice` from Features/Welcome. Also ported: `InputMethod`, `CategorySource`, `VoiceFailureReason.from` and `JoinFailureReason.from`.
- `Buckets` (count, millis, daysAgo, errorDays), `Screen` (with `fromRoute`), and `AnalyticsEventMapper` /
  `MappedEvent`, which enforces the GA4 limits and collapses custom categories.
- Protocols `AnalyticsRepository` and `CrashReporter` (+ `CrashKey`), with no-op implementations and
  Firebase implementations: `FirebaseAnalyticsRepository` (`import FirebaseAnalytics` from the `FirebaseAnalyticsCore`
  product, so no ad-id support) and `FirebaseCrashlyticsCrashReporter`, which applies the policy inside `recordNonFatal`.
- `ErrorReportingPolicy` (ERR-03): only `.unknown` and `.database` are reported. Its switch is exhaustive with no default.
- `TelemetryConsent` (TEL-02) sits on F42's `TelemetryConsentStore`, so there is no second store. Each change is applied at the vendor,
  and `applyPersisted()` re-applies the stored choice at launch. It also conforms to `TelemetryConsentStore`.
- `TelemetryMarkers` (suite `telemetry_markers`, Android key format), `Throttle` (monotonic clock) and `TelemetryContext`
  (app start, user changes, screen keys, and throttled data-shape counts read from the DAOs).
- `FirebaseSettings.resolve` + `TelemetryVendors.make` (TEL-01): Firebase is configured with
  `FirebaseOptions(googleAppID:gcmSenderID:)` + `apiKey` + `projectID` only when the environment isn't dev and all four
  Info.plist values are non-blank. Otherwise the no-ops are used and Firebase is never touched. `FirebaseApp.configure()` is never called without options.
- Errors: `AppError.Kind` (+ Android class names, for the `app_error` key). `ErrorReporter` is a closure `AppErrorReporter`
  that contains a throwing closure. The `AppErrorReporter` protocol signature is unchanged.
- App wiring (`AppContainer`):
  - `live()` builds the vendors before the database opens.
  - SafeCall reports through `ErrorReporter(crashReporter:)`.
  - `start()` runs `telemetryContext.onAppStart()` (consent first) and follows `observeDataOwner` for the Supabase UUID identity.
  - The Welcome seam now tracks `welcome_choice`.
  - Test and sample containers default to `.noOp`.
- TEL-05: nothing adds AdSupport, ATT or `NSUserTrackingUsageDescription`.

## Acceptance
I ran only the mapper class on its own. The other counts are the number of test methods in each file. All of them pass in the full run.
- [done] AnalyticsEventMapperTests ≥ 18: 18 (ran with `-only-testing`: `VERIFY PASS: 18 tests, 0 failures`)
- [done] BucketsTests ≥ 8: 8
- [done] FailureReasonsTests ≥ 2: 2
- [done] TelemetryMarkersTests ≥ 6: 6
- [done] TelemetryContextTests ≥ 8: 8
- [done] TelemetryConsentTests ≥ 7: 7
- [done] SafeCallReportingTests ≥ 7: 7
- [done] ErrorReportingPolicyTests ≥ 8: 8
- [done] No `NSUserTrackingUsageDescription` in BabeGetThis or project.yml (grep finds nothing)
- [not verified by me] No AdSupport.framework in the built app: `otool` is not on my allowed command list. Nothing links
  AdSupport (only `FirebaseAnalyticsCore` and `FirebaseCrashlytics`; project.yml is untouched). The orchestrator's check will confirm it.
- [done] Full suite: `VERIFY PASS: 1101 tests, 0 failures`

Last full `./scripts/verify.sh bgt-night-1`: `VERIFY PASS: 1101 tests, 0 failures`.
Extra: `FirebaseSettingsTests` (4) tests the configure-or-no-op decision.

## Blocked
- None. Two commands were denied and not retried another way: `grep` on the shared SPM checkout's Package.swift (I read it with the Read tool instead), and `otool`, which isn't on my list.

## Follow-ups
- Settings toggles: `SettingsView` builds its own `SettingsViewModel()` with the plain store, which is in Features and not owned by this task. A toggle
  is therefore stored at once but only reaches the SDKs at the next launch (`applyPersisted`). Fix: pass `container.telemetryConsent`
  (it is a `TelemetryConsentStore`) into `SettingsViewModel(consent:)`.
- Screen tracking: `TelemetryContext.onScreen(_:)` is ready, but no navigation calls it yet. Hook it into RootView and the list
  navigation together with F45's view-model events (TEL-04).
- `TelemetryMarkers` is built, but nothing uses it yet (F45: first_item_added, first_list_completed, shared_list_first_edit).
- Analytics collection starts the moment Firebase is configured, so consent is applied straight after that, before any event. To get
  zero collection before consent, add `FIREBASE_ANALYTICS_COLLECTION_ENABLED = NO` to Info.plist (project.yml is not owned).
