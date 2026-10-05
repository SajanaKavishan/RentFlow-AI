# Tenant pull-to-refresh and maintenance preview

Work remains on `feature/mobile-ui-redesign`. No backend, authorization,
maintenance eligibility, production navigation, or model changes were made.
Existing staged work was preserved. No commit, push, PR, or branch operation
was performed.

## Refresh behavior

Both Tenant Maintenance and My Applications now place the native
`RefreshIndicator` around their list state. Loaded lists, successful empty
results, and errors use scrollables with `AlwaysScrollableScrollPhysics`.
Empty and error layouts use available viewport constraints rather than a fixed
device height.

The two normal empty-state **Refresh** buttons were removed. Applications keeps
**Browse properties** and its existing navigation. Maintenance keeps **Retry**;
Applications keeps its existing **Try again** error action. Pulling an error
state also retries through the same service flow.

Refresh reuses the existing load methods and service calls. Concurrent refresh
callbacks share one pending operation. `FutureBuilder` retains confirmed
content while the new future is pending; the full loading state appears only
for the initial load. The indicator stays within the page body, above bottom
navigation.

## Debug preview

From `mobile/rentflow_mobile`, explicitly launch:

```powershell
flutter run --debug -t lib/debug/maintenance_preview.dart
```

The separate entry point renders `MyMaintenanceRequestsScreen` and injects a
typed in-memory maintenance service. That screen opens the existing property
chooser and `CreateMaintenanceRequestScreen`, whose production confirmation
panel handles the returned `MaintenanceRequest`. Cards, form validation,
category and priority controls, access notes, Track Request, and New Request
are the same widgets used by the app. A PREVIEW banner identifies the target.

Available fixtures include:

- Submitted/Open: kitchen faucet, description, initial status history, and
  `kitchen-faucet.jpg` attachment metadata.
- In progress: bedroom outlet, description, and Submitted → Assigned →
  In progress history.
- Resolved: refrigerator, description, completion date, and history ending
  with Completed and a repair note.
- New Request: all seven supported categories and Low, Normal, High, Emergency.
- Successful submission: deterministic UUID and timestamp, supported summary
  fields, tracking an expanded new request, and resetting the form.

All fixture dependencies live under `lib/debug`. The normal app does not
import them. The dependency factory rejects profile/release use before setup;
an offline HTTP client rejects any unimplemented network call. Authentication
uses a preview-only in-memory session and the existing `AuthController`.
The `.gitignore` exception permits this source directory to be tracked.

Normal New Request still calls the production tenant-property lookup and
shows **No associated properties** when it returns no association. Completed
viewings/applications do not establish maintenance eligibility.

## Files changed for this task

- Repository `.gitignore`.
- `lib/features/maintenance/screens/my_maintenance_requests_screen.dart`.
- `lib/features/rental_applications/screens/my_rental_applications_screen.dart`.
- `lib/debug/maintenance_preview.dart`.
- `lib/debug/maintenance_preview_dependencies.dart`.
- `test/tenant_pull_to_refresh_test.dart`.
- `test/maintenance_preview_test.dart`.
- `test/tenant_maintenance_redesign_test.dart`.
- `test/tenant_application_journey_test.dart`.
- This report.

## Validation

The 26 new tests cover actual pull gestures in loaded/empty/error states,
content retention, request coalescing, explicit error retries, Browse properties,
bottom-navigation interaction, 320px width, 720×1560 at DPR 2, 1080×2340 at DPR 3,
and 100%/200% text scale. Preview tests cover the real overview, filters, expanded
details and attachment metadata, validation, supported fields, submission,
tracking, form reset, offline transport, and production import isolation.
Existing production form tests include keyboard insets and text scaling.

Focused command:

```powershell
flutter test test/tenant_pull_to_refresh_test.dart test/maintenance_preview_test.dart test/tenant_maintenance_redesign_test.dart test/maintenance_screen_test.dart test/tenant_application_journey_test.dart test/rental_application_ui_test.dart test/rental_application_wizard_test.dart test/rental_application_submit_test.dart test/shared_shell_test.dart test/tenant_quick_action_destinations_test.dart test/maintenance_api_service_test.dart test/maintenance_request_model_test.dart --reporter expanded
```

| Check | Result |
| --- | --- |
| Focused tests, including eligibility and real navigation regressions | 206 passed |
| `flutter analyze` | Passed; no issues |
| `flutter test --reporter expanded` | 1,233 passed |
| `flutter build apk --debug` | Passed |
| `flutter build apk --debug -t lib/debug/maintenance_preview.dart` | Passed |
| `git diff --check` | Exit 0; no whitespace errors |

APKs are retained separately under `build/app/outputs/flutter-apk/`:
`rentflow-debug.apk` is the normal app and `maintenance-preview-debug.apk` is
the explicit preview target. `app-debug.apk` was restored to the normal app
artifact after the preview build. Both targets use the existing Android app
identifier, so installing one replaces the other.

The full repository diff check reported existing permission warnings for
unrelated files under `agent/.pytest_tmp_asus`; those files were untouched.
Scoped checks for this task and the existing staged Flutter work passed without
whitespace errors. Dart formatting checks passed. Build logs contain the
existing Gradle/Java native-access warning; both builds exited successfully.

## Remaining limitations

The preview is for offline UI inspection. State resets on restart. It does not
validate backend authorization, eligibility, leases, storage, or service-level
behavior. Attachment metadata, local upload, and delete are supported;
attachment downloads show an explicit unavailable message and never open a
network URL. The seeded JPEG has no downloadable payload. Device file picking
and Android keyboard rendering require manual emulator inspection.

APK build validation does not establish emulator visual fidelity. No emulator
launch or screenshot review was performed for this task.
