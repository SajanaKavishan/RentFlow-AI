# rentflow_mobile

## Tenant maintenance UI preview

Run the real tenant maintenance screens with an in-memory tenant, assigned
property, and sample requests (no login or backend required):

```powershell
flutter run -d chrome -t tool/maintenance_preview.dart
```

Use Chrome DevTools device mode (`Ctrl+Shift+M`) for a phone-sized viewport,
or replace `chrome` with a connected Android device ID from `flutter devices`.
The plus button opens property selection and the real request form. Submitting
adds a request in memory; restarting resets the preview.

For the unassigned-property state, append `--dart-define=PREVIEW_NO_PROPERTY=true`.
For an empty request list with an assigned property, append
`--dart-define=PREVIEW_EMPTY=true`.

## Authentication

Phase 2 stores only the JWT access token through `flutter_secure_storage`.
`ApiClient` adds the bearer header and centrally clears invalid sessions on
401 responses. `AuthController` restores the authoritative profile from
`/api/auth/me`; the client does not decode JWT data as profile truth.

Tenant viewing, rental application, and application document requests use the
authenticated JWT as tenant identity. Resource identifiers such as property,
application, viewing, and document IDs remain part of their API contracts.
Refresh tokens remain deferred to a later phase.

### Android emulator with a local API

Start the backend on port 5277, then run `tool/run_android_emulator.ps1` from
this directory in PowerShell. The script checks the backend, forwards the port
with `adb reverse`, and launches Flutter with
`API_BASE_URL=http://127.0.0.1:5277`. The forwarding must be set again after
the emulator or ADB restarts. Rebuild and relaunch the app when changing
`--dart-define`; hot reload does not replace a compiled API URL.
Pass `-DeviceId emulator-5554` if more than one emulator is connected.

The debug Android manifest permits cleartext HTTP for this local workflow.
Release builds should use an HTTPS `API_BASE_URL`.

A new Flutter project.

## Property discovery filters and Google towns

The discovery filter button expands an inline draft panel above the results.
Rent, location and amenities combine with the active search and quick filters.
`Show results` applies the draft; closing the panel discards it. Location chips
come from actual listings. `View more` reveals the full amenity catalog and
custom amenities returned by the property API. Selected amenities are required
together, using the same canonical keys as web preferences.

Android town suggestions use the native Google Places SDK (New), restricted to
Sri Lankan cities. Requests start after one character with a 350 ms debounce.
Selecting a suggestion resolves its city from address components and ends the
autocomplete billing session. No device location permission is required.

Configure `google.places.apiKey=YOUR_KEY` in the ignored
`android/local.properties`, preserving the existing SDK paths. Alternatively
pass `--dart-define=GOOGLE_PLACES_API_KEY=YOUR_KEY` when running/building Flutter.
Rebuild after changing either setting. Keys are never stored in tracked source.

In Google Cloud, enable Places API (New) and billing for the key's project.
Use Android application restrictions for `com.example.rentflow_mobile` and the
appropriate debug/release signing certificate SHA-1. A web key restricted to
HTTP referrers requires a separate Android key. Follow the
[Google Places setup](https://developers.google.com/maps/documentation/places/android-sdk/cloud-setup)
and [API key restrictions](https://developers.google.com/maps/api-security-best-practices).
Suggestions depend on Google's results; `K` is not guaranteed to rank any
particular city first. Missing keys, unsupported platforms or Google failures
leave manual town entry available. Native autocomplete is currently Android only.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
