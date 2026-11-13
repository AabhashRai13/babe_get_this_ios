# F12: Create-list chooser sheet and auth prompt (2026-11-13d)

## Summary
The Create button (FAB and the empty-state button) now opens a Type / Voice chooser sheet.
- **Type** closes the sheet and opens the existing name dialog.
- **Voice** opens the existing `VoiceCaptureSheet` for a live account session. Guests and expired sessions get an `AuthPromptDialog` titled "Sign in to use voice" instead.
- `ListsViewModel` gained the chooser, voice and auth-prompt state: `startCreating`, `pickType`, `pickVoice`, `authPrompt`.
- New files: `CreateListChooserSheet.swift`, `AuthPromptDialog.swift` (with `AuthPromptContent`, which also carries the share copy).
- `AppContainer.makeVoiceCaptureViewModel()` builds the real recorder and transcribe client.

## Acceptance checklist
- ListsViewModelTests/testVoiceRequiresAuthenticated runs (1 test, passes): done
- AuthPromptTests/testPromptNamesTheGatedFeature runs (1 test, passes): done
- Full suite: done

Last full `./scripts/verify.sh bgt-night-1`: `VERIFY PASS: 644 tests, 0 failures`

I did not run the `build/results/latest.json` executed-count check myself (python3 isn't on the allowed list); each filtered run executed 1 test.

## Blocked
Nothing.

## Follow-ups
- The auth prompt's "Sign in" and "Create account" buttons are no-op hooks (`onLogin` / `onRegister` on `ListsView`). Login and Register views are not reachable from the Lists screen yet.
- The voice sheet's `persist` returns a "not available yet" failure. Creating the list from voice results is F41.
- `makeVoiceCaptureViewModel` uses a fresh `KeychainTokenStore()` for the bearer token, because `AuthStateManager` doesn't expose its store.
