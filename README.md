# Taska Zurah Parent App

Flutter parent-facing app for Taska Zurah. The app includes attendance views, billing and invoice flows, teacher chat, memory journey screens, pickup QR scanning, notifications, and app-lock support.

## Validation Status

Validated on 2026-04-05:

- `flutter analyze`: no issues found
- `flutter test`: passes
- `flutter build apk --release`: passes
- `flutter build appbundle --release`: passes
- `flutter build web --release`: passes
- `flutter build web --release --wasm`: passes
- `flutter build windows --release`: passes

Follow-up client smoke on 2026-04-09:

- `build/windows/x64/runner/Release/parent_app.exe` launched successfully on Windows and stayed running until manually stopped.
- Rebuilt `flutter build web --release --wasm` after adding `web/firebase-messaging-sw.js`; local serve smoke returned `200` for both `/` and `/firebase-messaging-sw.js`, and the browser no longer hit the earlier Firebase Messaging service-worker `404`.
- Rebuilt `flutter build apk --release`, `flutter build appbundle --release`, `flutter build web --release --wasm`, and `flutter build windows --release` after replacing leftover `parent_app` shell branding on Android, web, and Windows; all four succeeded.
- The rebuilt web output now advertises `Taska Zurah Parent App` in `build/web/index.html` and `build/web/manifest.json`.
- The rebuilt Windows shell now reports `Taska Zurah Parent App` as both the main window title and EXE file metadata while keeping the existing `parent_app.exe` filename.
- Matching repo-side branding cleanup was also applied for macOS, iOS bundle naming, and Linux window titles, and those config files pass editor checks; macOS/Linux builds were not rerun from this Windows environment.

Current Android release output:

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

Current web release output:

- `build/web`

Current Windows release output:

- `build/windows/x64/runner/Release/parent_app.exe`

Current artifact manifest:

- `RELEASE-MANIFEST-2026-04-05.md`

To refresh that manifest from the current rebuilt artifacts, run from the repo root:

```bash
npm run manifest:parent-release
```

Known web caveat:

- Standard web release build works.
- WebAssembly build also works, but Flutter still labels wasm deployment as a newer feature, so target-browser smoke testing is still recommended before production rollout.

## Common Commands

Run from this folder:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
flutter build web --release
flutter build web --release --wasm
flutter build windows --release
```

From the repo root, refresh the release manifest with:

```bash
npm run manifest:parent-release
```

## Android Release Signing

- `android/key.properties.example` shows the expected release-keystore format.
- If `android/key.properties` exists, Android release builds use that keystore.
- If it does not exist, release builds fall back to debug signing so local validation can still run.
- When the fallback is used during a release build, Gradle now emits a warning so the build is not mistaken for a publish-ready Android artifact.
- For Play Store or production Android distribution, provide a real keystore via `android/key.properties` before publishing.

For the exact Android publish/signing sequence, see [ANDROID-RELEASE-HANDOFF.md](ANDROID-RELEASE-HANDOFF.md).

For the concrete artifact hashes, sizes, version metadata, and current signer state, see [RELEASE-MANIFEST-2026-04-05.md](RELEASE-MANIFEST-2026-04-05.md).

## iOS Handoff

The repo-side iOS preparation is already done:

- `ios/Podfile` is present
- Runner bundle IDs are aligned to `com.example.parentAppFixed`
- `ios/Runner/Info.plist` includes camera, Face ID, and background notification modes

Remaining iOS work must be completed on a Mac:

1. Add `ios/Runner/GoogleService-Info.plist` for the Firebase iOS app that matches bundle ID `com.example.parentAppFixed`.
2. Run `flutter pub get` in the app root.
3. Run `pod install` inside `ios/`.
4. Open `ios/Runner.xcworkspace` in Xcode.
5. Enable `Push Notifications` and `Background Modes` for the Runner target.
6. Confirm signing, team selection, and provisioning.
7. Run an iOS build or archive from Xcode.

If the iOS bundle ID needs to change, regenerate `lib/firebase_options.dart` and replace the matching `GoogleService-Info.plist` before building.

For the exact Mac-side sequence, see [IOS-HANDOFF.md](IOS-HANDOFF.md).

## Notes

- The current test suite is intentionally focused on billing-related pure logic rather than booting the full Firebase app in widget tests.
- Android and iOS use different package identifiers because they are configured as separate Firebase app entries.
- `flutter_secure_storage` was upgraded to a wasm-compatible release so web and wasm builds no longer hit the earlier `dart:html` / `dart:js_util` warning.
- `web/firebase-messaging-sw.js` is required for browser Firebase Messaging registration and background notification handling; it is now present in source and verified in the rebuilt web output.
- Platform shell metadata is now aligned with Taska Zurah branding on Android, web, and Windows, and the iOS display name has been updated in `ios/Runner/Info.plist` for the eventual Mac-side handoff.
- macOS bundle metadata now also aligns with the Apple Firebase identity in `lib/firebase_options.dart` by using `com.example.parentAppFixed` for the Runner product and `com.example.parentAppFixed.RunnerTests` for RunnerTests.
- The canonical Cloud Functions deploy target for this workspace remains `teacher_app_taskazurah/functions`; `parent_app_taskazurah/functions` is retained only as a legacy parity mirror and is not used by the repo-level billing deploy scripts.
