# F41: voice entry points (2026-11-14a)

## Summary
- The mic inside a list now saves spoken drafts straight into that list (VOICE-06, no review step).
  New `ListDetailVoiceSave.swift` has `saveVoiceDrafts(_:intoList:using:)`, which calls
  `addItemsToList(listId:drafts:)` and maps `AppError` to `VoiceError.unknown(message)`, as
  `ListsViewModel.createListWithVoice` does. The `persist:` argument in `ListDetailPlaceholderView.swift`
  (the TODO(F41) line) is the only edit in that file.
- Drafts never go through `ItemDraft.isValid` or `ListDetailViewModel.add(_:)`, so an empty quantity is saved.
- `AutoNameVoiceListTests`: all 10 Android cases ported. `autoNameVoiceList` needed no change.
- `VoiceListSaveTests`: three quantity-less drafts create a new list with three items, and go into an existing
  list as three items. It also covers appending to existing items, the error message and a thrown error.

## Acceptance checklist
- AutoNameVoiceListTests, 10 or more executed: done
- VoiceListSaveTests/testSpokenItemsWithoutQuantityAreAllSaved, 1 executed: done
- Full suite: done

## Verify
Focused run (both classes): `VERIFY PASS: 14 tests, 0 failures`
Last run, full suite: `VERIFY PASS: 832 tests, 0 failures`
Ran on bgt-night-4, not the "iPhone 18 Pro" in the acceptance commands.

## Blocked
Nothing.

## Follow-ups
- The new list's name in `ListsViewModel.createListWithVoice` is unchanged.
