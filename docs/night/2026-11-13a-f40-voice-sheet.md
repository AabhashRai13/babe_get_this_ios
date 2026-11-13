# F40: Voice capture sheet UI with microphone permission

## Summary
Ported Android `VoiceCaptureSheet.kt` and its voice sheet cases.
- `VoiceCaptureSheetModel` is the view state model. It holds the permission, auto-start, Done auto-dismiss and reset, and type-instead logic around the existing `VoiceCaptureViewModel`, and maps state to an Equatable `VoiceCaptureSheetContent` with the exact Android copy.
- `MicrophonePermissionProviding` is the permission seam; `SystemMicrophonePermission` uses `AVAudioApplication`. Tests use a fake.
- `VoiceTranscribingCopy` advances 3 lines every 2.5 s (injectable sleep) and holds on the last.
- `VoiceCaptureSheet` is the SwiftUI view, using AppColors, AppMetrics and the shared button styles. No entry points (that is F41).
- The recording view uses a plain SF mic symbol and a timer in place of Android's animated pebble mascot and waveform.

## Acceptance checklist
- testNeedsPermissionOffersAllowMicrophone (executed, passes): done
- testTranscribingCopyAdvancesEvery2_5Seconds (executed, passes): done
- Full suite: done

Last verify: `VERIFY PASS: 368 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- Pebble mascot and animated waveform (visual parity with Android).
- F41 should host the sheet and pass `persist`, `onDismiss` and `onSwitchToType`.
