# rentflow_mobile

## Authentication

Phase 2 stores only the JWT access token through `flutter_secure_storage`.
`ApiClient` adds the bearer header and centrally clears invalid sessions on
401 responses. `AuthController` restores the authoritative profile from
`/api/auth/me`; the client does not decode JWT data as profile truth.

Refresh tokens and the migration of temporary `tenantId` parameters to the
backend JWT identity are deferred to a later phase.

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
