# F03 UI components report

## Summary
Ported Haptics (named intents, protocol seam `HapticPlaying`, Android's collapse: Light alone; Medium/Heavy/Success share one effect), SwipeableCard (controller fires once per settled swipe; red/green at 90%, radius 14), SettingsRow (model + view, optional icon/subtitle/trailing) and BgtTopAppBar (large/small variants, Light haptic on nav and action taps, custom action slot). Tests in `BabeGetThisTests/DesignSystem/ComponentTests.swift`.

## Acceptance checklist
- HapticsTests/testHapticMapMatchesAndroid: done
- SwipeableCardTests/testSwipeFiresOncePerSettledSwipe: done
- TopAppBarTests/testNavAndActionTapsPlayLightHaptic: done
- SettingsRowTests (4 tests): done
- Full suite: done

Only the full `./scripts/verify.sh bgt-night-3` was run (the -only-testing forms are not on the allowed list); all these tests are in that run.

`VERIFY PASS: 131 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- SettingsRow tests exercise a model (no SwiftUI rendering test, as there is no ViewInspector); the Android tests used Compose rendering.
- The swipe gesture and view layout were not checked on screen.
- Swipe colours are named constants in SwipeableCard.swift, not asset-catalog colours.
