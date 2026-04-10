# Android Release Handoff

This document covers the remaining Android publishing steps for `parent_app_taskazurah`.

## Current Repo State

Already prepared in source control:

- `android/app/build.gradle.kts` supports release signing via `android/key.properties`
- `android/key.properties.example` documents the expected keystore fields
- Release builds fall back to debug signing when `android/key.properties` is missing
- Release builds now emit a warning when that debug-signing fallback is used

Already validated on 2026-04-05:

- `flutter analyze`
- `flutter test`
- `flutter build apk --release`
- `flutter build appbundle --release`

Current Android outputs:

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

## Required For Real Android Publishing

Before Play Store or production Android distribution, you still need:

1. A real Android release keystore.
2. A real `android/key.properties` file.
3. Confirmation that the chosen keystore is the long-term signing key for this app.

## Create Local Release Signing Config

From the app root, copy the example file:

```bash
cp android/key.properties.example android/key.properties
```

Then replace the placeholder values in `android/key.properties`:

```properties
storeFile=../keystores/parent_app_release.jks
storePassword=your-store-password
keyAlias=your-key-alias
keyPassword=your-key-password
```

Notes:

- `storeFile` is resolved relative to `android/`
- `android/key.properties` is already ignored by Git
- `*.jks` and `*.keystore` files are also ignored by Git

## Generate A Keystore

Example using Java `keytool`:

```bash
keytool -genkeypair \
  -v \
  -keystore parent_app_release.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias parent-app-release
```

Store the resulting keystore somewhere outside version control, then point `storeFile` at it.

## Build Commands

From the app root:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
```

Use the AAB for Play Store submission:

- `build/app/outputs/bundle/release/app-release.aab`

Use the APK only for direct installation/testing:

- `build/app/outputs/flutter-apk/app-release.apk`

## Sanity Checks Before Publishing

1. Confirm the release build does not log the debug-signing fallback warning.
2. Confirm `android/key.properties` points at the intended production keystore.
3. Keep a secure backup of the keystore and passwords.
4. Confirm the app bundle is the artifact uploaded to Play Console.

## Remaining Risk

- Without a real release keystore, Android builds are valid for local validation only, not for production distribution.