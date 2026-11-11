# F39: Voice recorder and capture view model (night 2026-11-12b)

## Summary
- `AVVoiceRecorder` (AVAudioRecorder, .m4a AAC 16 kHz mono, 30 s cap, system start tone played before the mic opens) behind the `VoiceRecording` protocol.
- `VoiceCaptureViewModel` (`@MainActor @Observable`): record, transcribe, persist; ported from Android's VoiceCaptureViewModel, including abandonment-vs-reset telemetry, file deletion in all outcomes, and cancel aborting tone, transcribe and persist.
- `TranscribedItem.toItemDraft()` maps to the existing `ItemDraft` (absent optionals become empty strings, `category` becomes `categoryId`).
- Tests use a fake recorder, fake transcriber and recording analytics. No real audio is recorded.

## Acceptance checklist
- VoiceCaptureViewModelTests, at least 30 executed: done (32 executed)
- ToItemDraftTests, at least 11 executed: done (12 executed)
- AudioRecorderTests/testRecordingFileIsDeletedAfterUse, 1 executed: done
- Full suite `./scripts/verify.sh bgt-night-4`: done

Last verify line: `VERIFY PASS: 228 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- No analytics layer exists in the repo, so `VoiceCaptureAnalytics`/`VoiceCaptureEvent` are local to this feature (default is a no-op). Wire to Firebase in the container later.
- Start tone uses system sound 1113; Android's `record_start` raw resource was not ported (resources are outside owned paths).
- Real `AVVoiceRecorder` is untested (needs a device mic); the sheet and permission request are F40.
- `ItemDraft` has non-optional strings, so the Android null assertions became empty-string assertions.
