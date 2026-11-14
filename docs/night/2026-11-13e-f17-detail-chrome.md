# F17: List detail chrome (run 2026-11-13e)

## Summary
- `ListDetailChromeModel` (new): voice FAB gate and the ordered top-bar actions (`ListDetailChromeModel.topBarActions` = Share live, Share as text).
- Voice FAB: always-shown mic button ("Add by voice") above the "+ Add" FAB. Medium haptic. Not `.authenticated` → existing `AuthPromptDialog` (voice copy), Sign in / Create account open `AuthSheet` login / register like the Lists screen. Authenticated → `VoiceCaptureSheet` for the list.
- Top bar: "Share live" (signed out → share auth prompt, as in Android's test; signed in → placeholder sheet, F34), "Share as text" (system share sheet with the list name, via `shareTextProvider` that F18 fills).
- Tests: `ListDetailChromeTests` (6 tests, including the two acceptance tests).

## Acceptance checklist
- testVoiceFabPromptsSignInUnlessAuthenticated: done
- testTopBarActionsAreShareLiveThenShareAsText: done
- Full `./scripts/verify.sh`: done

## Last verify.sh result
`VERIFY PASS: 692 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- F41: the voice sheet's `persist` is a TODO that returns a failure; transcribed items are not yet added to the list.
- F18: set `shareTextProvider` to the list formatter.
- F34: replace the Share live placeholder sheet with the share dialog.
- Strings use SwiftUI literals; the String Catalog (outside owned paths) was not edited.
