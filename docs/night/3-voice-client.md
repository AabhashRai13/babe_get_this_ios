# Task 3: Voice transcribe client

## Summary
Added `TranscribeClient` (`BabeGetThis/Core/Voice/`), a port of Android's `RemoteVoiceRepository` and `TranscribeDtos`.
It POSTs a multipart upload to `{apiBaseURL}transcribe` with a Bearer token and a 60-second timeout, then maps the
response to `ItemDraft`s. Errors use `VoiceError`, which mirrors Android's AppError copy and its status mapping.
No recording and no UI. Tests use a `URLProtocol` stub injected through a custom `URLSessionConfiguration`.

Files: `TranscribeClient.swift`, `TranscribeDtos.swift` (DTOs and `ItemDraft`), `VoiceError.swift`,
`BabeGetThisTests/Voice/TranscribeClientTests.swift` (13 tests: the 12 Android cases plus a quantity/unit flatten case).

## Acceptance checklist
- POST `{apiBaseURL}transcribe`, multipart, part `audio`, filename `*.m4a`, `audio/mp4`, Bearer header, 60s timeout: done
- Response maps to items, quantity and unit merged, `location` becomes `shop`: done
- HTTP and decoding errors map to the Android categories: done
- 12 `RemoteVoiceRepositoryTest` cases ported with a URLProtocol stub, no real network: done
- No recording or UI: done
- `./scripts/verify.sh bgt-night-3` passes: done

## Last verify
`VERIFY PASS: 33 tests, 0 failures`

## Blocked
Nothing.

## Follow-ups
- `TranscribeClient` takes `baseURL`, a token closure and an `isOnline` closure. `AppContainer` has to wire them
  (`AppConfig.apiBaseURL`, the Supabase session token, a network monitor); that is outside this task's owned paths.
- `VoiceError` is local to `Core/Voice`. Merge it into a shared app-error type if one is introduced.
