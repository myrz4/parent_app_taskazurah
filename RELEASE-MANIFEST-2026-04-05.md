# Release Manifest - 2026-04-05

This file captures the validated parent app release artifacts produced during the 2026-04-05 rollout pass and refreshed after the 2026-04-09 follow-up rebuilds.
Regenerate from the repo root with `npm run manifest:parent-release`.

## Build Identity

- App: `parent_app_taskazurah`
- Version: `1.1.1+3`
- Android application ID: `com.example.parent_app`
- iOS bundle ID configured in Firebase/Xcode: `com.example.parentAppFixed`

## Validation Completed

The following commands passed on Windows:

- `flutter analyze`
- `flutter test`
- `flutter build apk --release`
- `flutter build appbundle --release`
- `flutter build web --release`
- `flutter build web --release --wasm`
- `flutter build windows --release`

Follow-up rebuilds also passed on 2026-04-09 after the web Firebase Messaging service-worker fix and platform-shell branding cleanup:

- `flutter build apk --release`
- `flutter build appbundle --release`
- `flutter build web --release --wasm`
- `flutter build windows --release`

## Android Artifacts

### APK

- Path: `build/app/outputs/flutter-apk/app-release.apk`
- Size: `467,880,985 bytes`
- SHA-256: `D95953C2D43A537E59E5B63382467687DB9869BFCE9C4FF2E0892C5459DF1CB1`
- Last write time: `2026-04-09 01:25:24`

Signing state:

- Current signer DN: `C=US, O=Android, CN=Android Debug`
- Current signer SHA-256: `2129c51a1d1057dfbd55a85ec4f18b13b2fb154a40f0b35d2a238c2c895b4cf9`
- `android/key.properties` status during this build: `missing`

Interpretation:

- This APK is valid for local validation and device installation.
- It is not the final publish-ready Android release until a real release keystore is supplied.

### App Bundle

- Path: `build/app/outputs/bundle/release/app-release.aab`
- Size: `56,870,596 bytes`
- SHA-256: `7F44665A984D952B5E6932ABF30B890BC68C347E6DA15924654995A74C32F64F`
- Last write time: `2026-04-09 01:33:23`

Interpretation:

- The AAB build path is working.
- For Play Store upload, rebuild with a real release keystore configured through `android/key.properties`.

## Web Artifact

- Path: `build/web`
- Standard web build: passed
- Wasm web build: passed
- `index.html`: `1,311 bytes`, last write `2026-04-09 01:23:31`
- `manifest.json`: `1,023 bytes`, last write `2026-04-09 01:23:20`
- `firebase-messaging-sw.js`: `944 bytes`, last write `2026-04-09 01:17:37`

Notes:

- WebAssembly compilation now succeeds after the `flutter_secure_storage` upgrade.
- The built web output now includes `firebase-messaging-sw.js`, so browser Firebase Messaging registration no longer falls back to a missing service-worker path.
- Web metadata now advertises Taska Zurah Parent App / Taska Zurah instead of the earlier boilerplate placeholders.
- Browser smoke testing is still recommended before production wasm deployment.

## Windows Artifact

- Path: `build/windows/x64/runner/Release/parent_app.exe`
- Size: `14,480,384 bytes`
- SHA-256: `43CD5546C653342D6BD80A86EB7FF5AECAA35092CDF1162FD671A98D2B7C7634`
- Last write time: `2026-04-09 01:23:47`
- File description / product name: `Taska Zurah Parent App`
- Company name: `Taska Zurah`

## Remaining External Steps

### Android publishing

- Provide a real release keystore.
- Create `android/key.properties` from `android/key.properties.example`.
- Rebuild the APK/AAB so they are no longer debug-signed.

See `ANDROID-RELEASE-HANDOFF.md`.

### iOS completion

- Complete the Mac-side steps in `IOS-HANDOFF.md`.

## Notes

- Payment remains intentionally in dummy mode for the current rollout.
- The current Android artifacts are still debug-signed because `android/key.properties` remains absent.
- Repo-side macOS, iOS bundle-name, and Linux branding cleanup was also prepared on 2026-04-09, but those targets were not rebuilt from this Windows environment.
- This manifest is a release traceability snapshot, not a substitute for the Android and iOS handoff docs.
