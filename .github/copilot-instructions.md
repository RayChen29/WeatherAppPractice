## Purpose
Short, actionable guidance for AI coding agents working on this Flutter project.

## Quick facts (what to open first)
- App entry: `lib/main.dart` — a small, single-screen Flutter app with a `StatefulWidget` (`MyApp`).
- Dependencies: `pubspec.yaml` — notable packages: `http` (networking) and `geolocator` (location).
- Tests: `test/widget_test.dart` — run with `flutter test`.

## Quick start (commands you can run)
- flutter pub get  # install deps
- flutter run -d <device-id>  # run on connected device or emulator
- flutter build apk  # build Android APK
- flutter test  # run unit/widget tests

## Architecture & patterns (in-repo evidence)
- This repo is a simple Flutter app (no framework like Provider/Bloc used). Logic lives in `lib/main.dart` (validation, UI, TODOs for network/geolocation).
- Network calls should use the existing `http` import and `dart:convert` for JSON (see `lib/main.dart`).
- Location uses `geolocator` — remember to handle runtime permissions and add required platform keys in `android/` and `ios/Runner/Info.plist`.

## Project-specific conventions
- Small, single-file app: make minimal, incremental edits to `lib/main.dart` unless you intentionally add new modules.
- The code contains TODO comments (search for "todo") — preserve or convert them to tracked issues if implementing.
- Validation pattern: ZIP code validation is done inline in `_handleSubmit()` (5 digits). Follow that style for small, self-contained features.

## Integration points & pitfalls
- Geolocation: `geolocator` requires AndroidManifest/iOS Info.plist permission strings. Check `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist` before testing on device.
- Networking: API keys (e.g., OpenWeatherMap) are not present. Never commit secrets; prefer environment/config file excluded from VCS.

## Files to look at when changing behavior
- `lib/main.dart` — input handling, validation, and UI.
- `pubspec.yaml` — add dependencies or assets here.
- `test/widget_test.dart` — add tests when changing UI behavior.
- `android/` & `ios/` folders — platform-specific permission and build config (Gradle Kotlin scripts are used: `*.kts`).

## Example micro-tasks (how to implement common changes)
- Add OpenWeather integration: add dependency in `pubspec.yaml`, create `lib/src/weather_service.dart` using `http`, decode JSON with `dart:convert`, and call from `_handleSubmit()`.
- Add location button functionality: implement `_getZIP()` to call `Geolocator.getCurrentPosition()`, reverse-geocode externally or via a geocoding API, then populate `_zipController.text`.

## Testing & validation
- Use `flutter test` for unit/widget tests.
- Run on a real device when testing geolocation or platform permissions: `flutter run -d <device-id>`.

## Security & CI notes
- No CI config detected—run checks locally. Do not add secrets to the repo. If you add CI, include `flutter pub get` and `flutter test` steps and ensure the Flutter SDK version is compatible (repo targets Dart SDK ^3.9.0).

If anything here is unclear or you want me to expand examples (e.g., a small weather service or CI job), tell me which part to flesh out.
