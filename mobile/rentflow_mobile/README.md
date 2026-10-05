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

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
