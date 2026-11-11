# Babe, Get This — iOS

Native Swift/SwiftUI port of the Android app at `../android/Babe-get-this`.
The Android app and its docs ARE the spec. Extract decisions from them; don't re-ask the owner.

## Hard rules
- **Never edit anything under `../android/`.** It is a read-only reference clone.
- **Never `git push`** without asking the owner first, every single time.
- **No `Co-Authored-By` or "Generated with Claude" lines** in commits or PRs.
- **Never touch production Supabase.** The project NAMED "babegetthis-staging"
  (ref `fpzjyusgqdzqituokrwq`) IS PRODUCTION. Real staging is "babe-get-this-real-staging"
  (ref `vdiheceziirgvbudxdxg`). Dev and tests use the local Supabase in Docker with
  migrations 001–006 from `../android/Babe-get-this/supabase/migrations`.
- No code signing, archiving or App Store uploads.

## Reference
- Android reference branch: `feat/got-this` (PR 39) until it merges into `main`.
- Read: `docs/technical-decisions/*`, `docs/product-decisions/*`, `docs/superpowers/specs/*`,
  `supabase/migrations/001-006`, `REALTIME_TEST_FINDINGS.md` (all under the Android folder).
- Parity spec for this app: `docs/PARITY.md` (once written).

## Stack
- SwiftUI, iOS 17+, `@Observable`, Swift 6 language mode.
- GRDB.swift (local DB), supabase-swift (Auth, PostgREST, Realtime), URLSession + AVAudioRecorder (voice),
  AuthenticationServices (Sign in with Apple), GoogleSignIn-iOS, Firebase (Analytics, Crashlytics).
- XcodeGen: `project.yml` is the source of truth; `*.xcodeproj` is generated and git-ignored.
- No DI framework: `AppContainer` is the composition root. MVVM + Repository, like Android.

## Key behaviour rules (from the Android app)
- Offline-first, exactly like Android: port `core/sync/SyncEngine.kt` (+ ShareRepository, paging, SyncTrigger)
  method by method into a Swift `actor`. Lists push before items; a list's first push is a plain INSERT.
  Always UPDATE existing local rows, never INSERT OR REPLACE.
- iOS v1 must NOT send `picked_up_at` (acts as a pre-Got-This client).
- Realtime: one channel `list-<id>` only while a list screen is open; every event or (re)subscribe → `catchUp(listId)`.

## Layout
```
project.yml            XcodeGen spec (targets, configs, schemes)
Config/*.xcconfig      Dev / Staging / Prod settings; Secrets.xcconfig is git-ignored
BabeGetThis/           App sources (App/, Core/, Features/, Resources/)
BabeGetThisTests/      XCTest unit tests
```

## Commands
```bash
xcodegen generate
xcodebuild -project BabeGetThis.xcodeproj -scheme BabeGetThis-Dev \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

## Environments
| Config  | Bundle ID                   | Supabase                       | Transcribe API                                     |
|---------|-----------------------------|--------------------------------|----------------------------------------------------|
| Dev     | com.babegetthis.ios.dev     | local Docker (127.0.0.1:54321) | http://127.0.0.1:8080/                             |
| Staging | com.babegetthis.ios.staging | real staging (vdiheceziirgvbudxdxg) | https://babegetthisapis-staging.up.railway.app/ |
| Prod    | com.babegetthis.ios         | production                     | https://babegetthisapis-production.up.railway.app/ |

Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and fill in keys.
