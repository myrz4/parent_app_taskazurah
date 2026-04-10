# iOS Handoff

This document covers the remaining iOS setup for `parent_app_taskazurah` that must be completed on a Mac.

## Current Repo State

Already prepared in source control:

- `ios/Podfile` exists
- Runner bundle ID is aligned to `com.example.parentAppFixed`
- `ios/Runner/Info.plist` includes:
  - `NSCameraUsageDescription`
  - `NSFaceIDUsageDescription`
  - `UIBackgroundModes` with `fetch` and `remote-notification`

Already validated on Windows:

- `flutter analyze`
- `flutter test`
- `flutter build apk --release`
- `flutter build web --release`

Not yet validated:

- iOS pod installation
- iOS signing
- iOS archive/build
- APNs capability wiring in Xcode

## Required Inputs

Before starting on a Mac, make sure you have:

1. A Mac with Xcode and CocoaPods installed.
2. The Firebase iOS app for bundle ID `com.example.parentAppFixed`.
3. The matching `GoogleService-Info.plist` for that Firebase iOS app.
4. An Apple Developer team that can sign the Runner target.

## Mac Terminal Steps

From the app root:

```bash
cd parent_app_taskazurah
flutter pub get
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

Notes:

- If `pod install` fails because repos are stale, run `pod repo update` and retry.
- `flutter build ios --release --no-codesign` is the fastest way to confirm the project compiles before dealing with distribution signing.

## Xcode Steps

Open:

```bash
open ios/Runner.xcworkspace
```

Then in Xcode:

1. Select the `Runner` target.
2. Verify `Bundle Identifier` is `com.example.parentAppFixed`.
3. Under `Signing & Capabilities`, select the correct team.
4. Add `Push Notifications` capability.
5. Add `Background Modes` capability.
6. Under `Background Modes`, enable:
   - `Remote notifications`
   - `Background fetch`
7. Add `GoogleService-Info.plist` to the `Runner` target if it is not already included.
8. Confirm the generated entitlements file is part of the Runner target after adding capabilities.

## Firebase Checks

Verify all of the following match the same iOS app registration:

- Xcode bundle ID: `com.example.parentAppFixed`
- `lib/firebase_options.dart`
- `ios/Runner/GoogleService-Info.plist`

If the bundle ID needs to change, do not patch only one place. Regenerate `lib/firebase_options.dart` and replace the plist with the matching Firebase app config.

## Feature-Specific Checks

After the first successful iOS launch, verify:

1. App starts without Firebase initialization failure.
2. Login flow still works.
3. Billing screens load.
4. Pickup QR scanner prompts for camera access and opens correctly.
5. App lock can request biometrics or Face ID without missing-plist-key crashes.
6. FCM token registration runs without iOS capability errors.

## Recommended Validation Order

1. `flutter build ios --release --no-codesign`
2. Xcode run on a physical device
3. Push capability verification
4. Archive build in Xcode

## Expected Remaining Risks

- Push notifications may still need APNs key or certificate setup in Apple Developer and Firebase Console.
- Device-only biometric and push behavior cannot be fully validated in a simulator.
- If the Firebase iOS app does not actually exist for `com.example.parentAppFixed`, the bundle ID or Firebase config must be corrected before build validation.