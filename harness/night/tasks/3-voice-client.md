# Task 3: Voice transcribe client
Branch `night/3-voice-client`. Simulator `bgt-night-3`.

## Owned paths
- `BabeGetThis/Core/Voice/`
- `BabeGetThisTests/Voice/`
- `docs/night/3-voice-client.md`

## Port from (Android, `origin/feat/got-this`)
`core/voice/data/remote/dto/TranscribeDtos.kt`, `RemoteVoiceRepository` and `RemoteVoiceRepositoryTest` (12 cases).
The base URL comes from `AppConfig.apiBaseURL` (`BabeGetThis/Core/Config/AppConfig.swift`; read it, don't edit it).

## Acceptance (immutable)
- `TranscribeClient` sends `POST {apiBaseURL}transcribe` as `multipart/form-data` with a part named `audio`, filename `*.m4a`,
  content type `audio/mp4`. Header `Authorization: Bearer <token>`. 60-second timeout.
- Response `{transcript?, items:[{name, quantity:Int?, unit?, category?, location?, note?}]}` maps to parsed items.
  Quantity and unit are merged into one string (same rules as Android); `location` becomes `shop`.
- HTTP and decoding errors map to the same categories Android uses.
- All 12 `RemoteVoiceRepositoryTest` cases ported (at least 12 `func test` in `BabeGetThisTests/Voice/`), using a `URLProtocol`
  stub injected through a custom `URLSessionConfiguration`. No real network.
- No recording or UI.
- `./scripts/verify.sh bgt-night-3` passes.
