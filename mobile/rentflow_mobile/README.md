# rentflow_mobile

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

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
