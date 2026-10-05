# Tenant Maintenance Task 2 - implementation and validation

Work remains on `feature/mobile-ui-redesign`. No commit, push, PR, branch change,
or production database update was performed. The supplied mock/current screenshots
were the visual reference; RentFlow's cream/olive palette and existing icons were
retained. The production overview, create screen and attachment API are reused.

1. **Architecture before changes.** ASP.NET Core/.NET 8, EF Core 8.0.29,
   Npgsql/PostgreSQL; `MaintenanceRequestsController` authorizes the actor,
   `MaintenanceRequestService` owns creation/transitions, and
   `MaintenanceAttachmentService` stores private R2-backed attachments. Requests
   use GUID route IDs, required Title (200), Description (4000), numeric
   Category/Priority/Status and legacy nullable TenantAccessNotes (1000).
   There was no public reference or structured access window. The exact existing
   enums, tenancy query, storage limits and client contracts were inspected
   before edits in [the audit](tenant-maintenance-task2-audit.md).

2. **Removed tenant create fields.** Separate Title and generic access-notes
   textarea. Historical titles/access notes and other clients' compatibility
   remain supported.

3. **Final mobile categories.** Plumbing (0), Electrical (1), HVAC / A/C (7),
   Appliances (2), Structural (3), Pest Control (5), Locks / Doors (8), Other (6),
   in that order. HVAC and LocksDoors are real appended backend enum values;
   Security (4) remains readable with its original meaning. Existing values were
   not renumbered. Flutter/web parsing and category labels were updated.

4. **Create priorities.** Emergency (3), High Priority (2), Normal (1).
   Historical Low (0) remains readable and usable by existing backend workflows.

5. **Description/title compatibility.** The mobile description has a real
   500-character counter and input limit; whitespace-only input cannot submit.
   The server retains its 4000-character description limit. An omitted/blank
   create Title is derived on the server from collapsed description whitespace
   and its first sentence, capped at 200 characters at a word boundary. If that
   sentence is only punctuation, the category provides a nonblank fallback. A supplied
   legacy Title remains accepted and validated. Existing update contracts keep
   their titles. Flutter never derives a production title.

6. **Preferred access design.** `PreferredAccessWindow` is serialized as
   `Morning`, `Afternoon`, or `Evening`; the labels are Morning 8-12,
   Afternoon 12-5, Evening 5-8. Creation requires a valid value. The database
   stores a nullable string with an allowed-value CHECK constraint so legacy
   rows retain null. Detail and summary DTOs return the value. Invalid/numeric
   API values are rejected. Flutter selects one choice and omits it from legacy
   detail when absent. The existing web form now sends this required field.

7. **Camera and permissions.** An injectable `image_picker` adapter performs
   native capture only after Take a photo is selected. Android delegates capture
   to the camera activity and needs no new app CAMERA permission; no broad
   storage/media permission was added. iOS has camera/photo usage descriptions.
   Denied/restricted access yields concise device-settings guidance. On iOS,
   Open settings uses the already-installed `url_launcher`; launch failure has a
   safe fallback. Android retains guidance because this adapter has no Android
   settings-intent launcher. No additional permission package was added.
   Configuration follows the official [image_picker documentation](https://pub.dev/packages/image_picker),
   [URL launcher documentation](https://pub.dev/packages/url_launcher), and
   [Apple settings API](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring).

8. **Gallery behavior.** Native multiple selection, cancellation without draft
   changes, minimal metadata (`requestFullMetadata: false`), client count
   enforcement, and Android lost-selection recovery. The Android 15 emulator
   displayed the system picker with access limited to selected photos. Native
   camera and gallery returned photos to the production form; the draft showed
   three selected photos. The source sheet presents both choices first.

9. **Photo limits/validation.** Up to five photos per request; each nonempty
   JPEG/PNG/WEBP must be at most 10 MiB. The mobile adapter checks filename
   extension, MIME and image signature, and checks native file size before
   reading bytes. Local thumbnails have accessible Remove actions. The backend
   retains its MIME/size contract and now enforces the five-photo quota under a
   PostgreSQL request-row lock, including concurrent upload attempts. Existing
   stored attachments are not removed. Post-create Add also checks size locally.

10. **Create/upload order.** Validate draft and selected files, POST exactly one
    request with the real property/category/priority/description/access values,
    then upload each photo once through the existing request attachment route.
    Uploads use the returned internal ID. The form prevents duplicate callbacks,
    disables controls while submitting, and shows create/upload progress. Detail
    and attachment metadata are fetched again before confirmation; a successful
    POST/upload response is retained if those refreshes fail.

11. **Partial upload failure.** The request remains created. Confirmation states
    how many photos could not upload and directs the tenant to Track Request's
    existing attachment Add workflow. Counts come from server metadata, or only
    confirmed successful upload responses if metadata refresh is unavailable.
    A create rejection preserves the entire draft and uploads nothing.

12. **Friendly reference.** PostgreSQL persists `MR-` plus the first 16 uppercase
    hexadecimal characters of the MD5 checksum of the canonical GUID string.
    This is a stable display checksum, not an authorization token. A stored
    computed column and unique index backfill legacy rows and prevent overriding
    or duplicate persisted references. The server's deterministic fallback
    supports non-relational tests. Flutter displays only the API reference; GUIDs
    remain internal route/ownership identifiers. No timestamp/client counter is
    used for production references.

13. **Eligibility.** The exact pre-existing `/properties/tenant/mine` query is
    now shared by lookup and server creation: the same tenant/property must have
    an Active lease whose inclusive date range contains the current UTC date,
    a matching Accepted offer, and matching Approved application. An application,
    viewing, unrelated property or expired/future/inactive lease cannot confer
    access. Ineligible create returns safe 403 ProblemDetails before persistence.
    Actor/ownership authorization remains in the controllers.

14. **Property UX.** One eligible property is automatic with its real title
    beneath the form heading and in confirmation. Multiple properties use an
    inline selector before categories; none is guessed. Zero eligible properties
    retains the blocking dialog with an active-lease explanation. Raw property
    IDs are not shown as context. Create 403/409 errors preserve the draft.

15. **Success screen.** Small check mark, centered Request Submitted, concise
    truthful copy, compact reference/category/priority/real-property/access/
    confirmed-photo-count/submitted-time summary, Track Request and New Request.
    No raw GUID, redundant title/status, invented technician, or 24-hour promise.
    Track refreshes and expands the created request; New clears description,
    photos, access choice and prior success/error state.

16. **Cards/detail.** Friendly references replace UUID subtitles. Preferred
    access is conditional on real data; historical notes remain visible.
    History continues to show returned events. Empty attachment headings and
    placeholder content are omitted; the existing Add action remains available.
    Uploaded metadata uses the existing server-loaded attachment list, Open,
    Delete and Retry workflow. No second local-only post-submit gallery was
    created. Overview tiles/header/card text were tightened to match the mock's
    hierarchy, with large-text wrapping retained.

17. **Migration.** Generated EF migration
    `20261005040047_AddTenantMaintenanceRequestExperience`, its Designer and the
    model snapshot. It adds only the nullable access string, stored computed
    reference, unique reference index and access CHECK. It was applied against
    disposable PostgreSQL schemas, including upgrading a legacy 3500-character
    description/Low-priority row. It has not been applied to a live database.

18. **Changed files.** The complete source inventory is below. Desktop plugin
    registrants and the lockfile are generated by `flutter pub get`; Android's
    main manifest required no edit. Landlord/technician screen content remains
    unchanged; their parsing of the extended shared enum is supported.

19. **Backend validation.** `dotnet build --no-restore`: zero warnings/errors.
    Focused maintenance/controller/storage/workflow plus PostgreSQL: **99 passed**.
    The new PostgreSQL suite alone: **3 passed**, covering legacy migration,
    concurrent unique references/access persistence, and six concurrent uploads
    producing exactly five stored photos with ownership checks. Full backend:
    **952 passed, zero skipped**. PostgreSQL 18 ran in a new task-owned cluster on
    loopback port 55439, using `rentflow_component3_test_maintenance_task2`; only
    its disposable schemas were mutated, and that temporary server was stopped.

20. **Flutter validation.** Focused form/media/access/reference/preview/refresh/
    attachment/navigation tests: **99 passed**. Full `flutter test`:
    **1247 passed**. Coverage includes 320px, 720x1560 at DPR 2, 1080x2340 at
    DPR 3, 200% text, keyboard insets, source sheet, long content, duplicate
    callback protection, denied permissions/settings support, create rejection,
    partial upload, truthful counts, Track and draft reset. Existing auth,
    applications, viewings, shell, landlord and technician tests also pass.

21. **Other checks/artifacts.** `flutter analyze`: no issues. Normal and separate
    offline-preview debug APKs build. The preview was also launched using
    `flutter run --debug -t lib/debug/maintenance_preview.dart
    --dart-define=MAINTENANCE_PREVIEW_USE_PLATFORM_PICKER=true -d emulator-5554`
    on Android API 35; native camera, gallery, confirmation and Track were checked.
    The normal APK remains `app-debug.apk` and `rentflow-debug.apk`; the default
    fixture preview is `maintenance-preview-debug.apk` under
    `mobile/rentflow_mobile/build/app/outputs/flutter-apk/`.
    Web compatibility tests: **12 passed**; scoped ESLint clean and Vite build
    passed. Vite's existing large-chunk warning and Java native-access warnings
    do not fail the builds. `git diff --check` and the scoped backend/mobile/web/
    docs check exit zero; the global command also reports pre-existing inaccessible
    agent pytest temporary paths. Those unrelated paths were left alone.

22. **Practical limits.** Apply the migration and run the updated API before
    using the updated normal client against a live database. Live R2/network
    upload was not exercised with credentials; storage/HTTP behavior is covered
    by backend and Flutter tests. iOS permission/settings execution needs an iOS
    device; this Windows session verified Android and injectable denial/settings
    behavior. Default preview photos and metadata are session-local/offline and
    its download endpoint intentionally has no live signed URL. The native picker
    option changes only photo capture, never preview authentication/networking.

## Source inventory

Paths below are relative to the repository root.

```text
backend/RentFlow.Api/Controllers/MaintenanceRequestsController.cs
backend/RentFlow.Api/Controllers/PropertiesController.cs
backend/RentFlow.Api/DTOs/Maintenance/CreateMaintenanceRequestDto.cs
backend/RentFlow.Api/DTOs/Maintenance/MaintenanceRequestResponseDto.cs
backend/RentFlow.Api/DTOs/Maintenance/MaintenanceRequestSummaryDto.cs
backend/RentFlow.Api/Data/ApplicationDbContext.cs
backend/RentFlow.Api/Data/Migrations/20261005040047_AddTenantMaintenanceRequestExperience.cs
backend/RentFlow.Api/Data/Migrations/20261005040047_AddTenantMaintenanceRequestExperience.Designer.cs
backend/RentFlow.Api/Data/Migrations/ApplicationDbContextModelSnapshot.cs
backend/RentFlow.Api/Models/MaintenanceCategory.cs
backend/RentFlow.Api/Models/MaintenanceRequest.cs
backend/RentFlow.Api/Models/MaintenanceReferenceCode.cs
backend/RentFlow.Api/Models/PreferredAccessWindow.cs
backend/RentFlow.Api/Services/MaintenanceRequestService.cs
backend/RentFlow.Api/Services/MaintenanceRequestServiceException.cs
backend/RentFlow.Api/Services/MaintenanceAttachmentService.cs
backend/RentFlow.Api/Services/TenantMaintenanceEligibility.cs
backend/RentFlow.Api.Tests/Controllers/MaintenanceRequestsAuthorizationTests.cs
backend/RentFlow.Api.Tests/Services/MaintenanceRequestServiceTests.cs
backend/RentFlow.Api.Tests/Services/MaintenanceTenancyFixture.cs
backend/RentFlow.Api.Tests/Services/TenantMaintenanceWorkflowTests.cs
backend/RentFlow.Api.Tests/Data/TenantMaintenancePostgresTests.cs
mobile/rentflow_mobile/ios/Runner/Info.plist
mobile/rentflow_mobile/lib/debug/maintenance_preview.dart
mobile/rentflow_mobile/lib/debug/maintenance_preview_dependencies.dart
mobile/rentflow_mobile/lib/features/maintenance/models/maintenance_request.dart
mobile/rentflow_mobile/lib/features/maintenance/screens/create_maintenance_request_screen.dart
mobile/rentflow_mobile/lib/features/maintenance/screens/my_maintenance_requests_screen.dart
mobile/rentflow_mobile/lib/features/maintenance/services/maintenance_api_service.dart
mobile/rentflow_mobile/lib/features/maintenance/services/maintenance_photo_picker.dart
mobile/rentflow_mobile/lib/features/maintenance/widgets/maintenance_photo_source_sheet.dart
mobile/rentflow_mobile/lib/features/maintenance/widgets/tenant_maintenance_ui.dart
mobile/rentflow_mobile/pubspec.yaml
mobile/rentflow_mobile/pubspec.lock
mobile/rentflow_mobile/test/maintenance_api_service_test.dart
mobile/rentflow_mobile/test/maintenance_preview_test.dart
mobile/rentflow_mobile/test/maintenance_request_model_test.dart
mobile/rentflow_mobile/test/maintenance_screen_test.dart
mobile/rentflow_mobile/test/tenant_maintenance_redesign_test.dart
mobile/rentflow_mobile/test/tenant_maintenance_workflow_test.dart
mobile/rentflow_mobile/linux/flutter/generated_plugin_registrant.cc
mobile/rentflow_mobile/linux/flutter/generated_plugins.cmake
mobile/rentflow_mobile/macos/Flutter/GeneratedPluginRegistrant.swift
mobile/rentflow_mobile/windows/flutter/generated_plugin_registrant.cc
mobile/rentflow_mobile/windows/flutter/generated_plugins.cmake
web/rentflow-web/src/features/maintenance/pages/TenantMaintenancePage.jsx
web/rentflow-web/src/features/maintenance/services/maintenanceEnums.js
web/rentflow-web/src/features/maintenance/services/maintenanceEnums.test.js
web/rentflow-web/src/features/maintenance/maintenanceWorkflow.test.jsx
docs/tenant-maintenance-task2-audit.md
docs/tenant-maintenance-task2-report.md
```

## Repeatable checks

Run backend commands in `backend/RentFlow.Api.Tests` (the build also works from
`backend/RentFlow.Api`). PostgreSQL tests require an explicitly disposable test
connection whose database name begins with `rentflow_component3_test`.

```powershell
dotnet build
dotnet test --filter "FullyQualifiedName~MaintenanceRequestServiceTests|FullyQualifiedName~TenantMaintenanceWorkflowTests|FullyQualifiedName~MaintenanceAttachmentServiceTests|FullyQualifiedName~MaintenanceRequestsAuthorizationTests|FullyQualifiedName~TenantMaintenancePostgresTests"
dotnet test --filter "FullyQualifiedName~TenantMaintenancePostgresTests"
dotnet test
```

Run Flutter commands in `mobile/rentflow_mobile`:

```powershell
flutter analyze
flutter test test/tenant_maintenance_workflow_test.dart test/tenant_maintenance_redesign_test.dart test/tenant_pull_to_refresh_test.dart test/maintenance_preview_test.dart test/maintenance_api_service_test.dart test/maintenance_request_model_test.dart test/maintenance_screen_test.dart
flutter test
flutter build apk --debug
flutter build apk --debug -t lib/debug/maintenance_preview.dart
flutter run --debug -t lib/debug/maintenance_preview.dart
```

The last command uses fixture photos by default. Add
`--dart-define=MAINTENANCE_PREVIEW_USE_PLATFORM_PICKER=true` to exercise native
camera/gallery against the offline preview service. Production source cannot
import the debug directory; the preview factory rejects non-debug builds and
its transport rejects network requests.

Task-specific logs and Android screenshots are retained under `.tmp/`;
`maintenance-task2-form.png`, `maintenance-task2-photo-sheet.png`,
`maintenance-task2-camera-selected.png`, `maintenance-task2-gallery-selected.png`,
`maintenance-task2-ready.png`, `maintenance-task2-success.png`, and
`maintenance-task2-tracked.png` record the visual/native checks.
