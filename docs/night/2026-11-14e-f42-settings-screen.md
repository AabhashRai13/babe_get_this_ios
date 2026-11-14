# F42: Settings screen (night 2026-11-14e)

## Summary
Replaced the F24 placeholder `SettingsView` (same type name, `title`, and initialiser) with the Settings screen:
Privacy section (Usage analytics and Crash reports toggles, both ON by default), About section (Rate the app, Privacy policy),
and the "Version <name> (<build>)" footer read from `CFBundleShortVersionString` / `CFBundleVersion`.
- `TelemetryConsentStore` protocol (frozen name) with `UserDefaultsTelemetryConsentStore` on `UserDefaults(suiteName: "telemetry_consent")`, keys `analytics_enabled` and `crash_reporting_enabled`.
- `SettingsViewModel` (`@Observable`), with version, App Store id and consent store injectable.
- "Rate the app" opens `https://apps.apple.com/app/id<BGTAppStoreID>?action=write-review` and is hidden while `BGTAppStoreID` is empty (or not numeric, e.g. an unexpanded `$(BGT_APP_STORE_ID)`). "Privacy policy" opens `https://babegetthis.com/privacy-policy.html`. Both use `openURL`.
- Rows use the existing `SettingsRow`. Strings are Android's wording, with "App Store" instead of Google Play.

## Acceptance checklist
- `testSectionsArePrivacyThenAbout` runs and passes: done
- `testVersionFooterFormat` runs and passes (verify.sh: `VERIFY PASS: 1 tests, 0 failures`): done
- Full suite: done

Last `./scripts/verify.sh bgt-night-2` line: `VERIFY PASS: 1006 tests, 0 failures`

I did not run the `python3 -c ... latest.json` half of the acceptance commands (not on my allowed command list); the orchestrator re-runs them.

## Blocked
- The brief asks to record the Rate-row iOS deviation in `docs/PARITY.md` under SET-02. That file is outside my owned paths, so I did not edit it.
  Text to add under SET-02: "iOS deviation: 'Rate the app' opens the App Store review page (`https://apps.apple.com/app/id<BGTAppStoreID>?action=write-review`) instead of Google Play, and the row is hidden while `BGTAppStoreID` is empty (no App Store listing yet)."

## Follow-ups
- Add the PARITY.md SET-02 deviation note above.
- F44: apply `TelemetryConsentStore` values to Firebase Analytics and Crashlytics.
- F50: port the Android SettingsTest toggle tests.
- SF Symbols for the rows (chart.bar, ant, star, hand.raised) are my picks for Android's Analytics, BugReport, StarRate and PrivacyTip icons.
- No UI-level tests of the screen itself; only the view model is covered.
