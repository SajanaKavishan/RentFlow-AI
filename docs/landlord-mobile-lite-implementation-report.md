# Landlord mobile lite workspace implementation

Validated on 2026-10-05 on `feature/full-app-polish`. No branch changes, commits, pushes, or PRs were made.

1. **Notification architecture audit.** Mobile previously used an authenticated notification inbox and unread-count API. The shared shell refreshed unread counts on resume. Viewing Details already refetched server completion permission on resume and at the server-supplied end time. Backend viewing actions already used `TimeProvider`, property ownership guards, and the existing completion endpoint.

2. **Existing local notifications.** No local-device notification package, scheduled notification service, Android notification permission handling, or Firebase/FCM infrastructure was present. Added `flutter_local_notifications` 21.0.0 and `timezone`, using existing secure storage for reminder allocations and the permission-attempt flag. Platform setup follows the [package's official documentation](https://pub.dev/packages/flutter_local_notifications/versions/21.0.0).

3. **Final Home layout.** Cream background; `LANDLORD HOME` eyebrow; actual first name with the shared Colombo time-aware greeting; notification bell and real unread badge; compact dark-olive hero; quick actions; optional real recent activity; compact web-workspace information banner. The top profile icon is absent. Greeting logic was extracted from Tenant Home and reused by both roles. Larger text stacks the quick-action cards and allows the greeting to wrap.

4. **Quick actions.** Viewing requests and Rental applications. No fabricated counts or additional management actions.

5. **Recent activity.** Uses existing recipient-scoped notification inbox events for `ViewingRequest` and `RentalApplication`, sorted by their real creation timestamps, with up to three items. Tapping opens the existing inbox. The section is omitted when relevant events are absent or the API is unavailable. No activity domain or synthetic events were introduced.

6. **Landlord navigation.** Existing order retained: Home, Viewing Requests, Applications, Maintenance, Profile. Maintenance is an implemented landlord workflow and remains accessible. Profile remains available from bottom navigation.

7. **Viewing list and details.** Connected the production screens to the existing authenticated `/api/properties/mine` endpoint and existing guarded property-viewing endpoints. All owned properties are included; a failed property fetch fails the whole collection instead of presenting a partial queue as complete. Lists retain pending-first ordering, loading/empty/error/retry states, pull-to-refresh, real tenant identity, notes, requested date/time, and status. Details show real property title, tenant, duration, requested date/time, note, landlord response, and existing approve/reject/completion actions. Existing approved-viewing contact disclosure rules are preserved. Missing display fields are described truthfully.

8. **Completion reminder architecture.** A single reminder service serializes reconciliation and account changes. Secure storage persists a collision-free viewing-to-notification-ID allocation. A host above the Navigator observes startup, resume, settled navigation, and successful viewing mutations. It fetches the complete authorized collection, schedules future reminders, removes disqualified reminders, and replaces changed schedules. Logout/account changes clear the previous owner's reminders.

9. **Timing source.** Device scheduling uses the exact server `completionEligibleAt` instant in UTC. The backend already defines this as requested start plus the booking's stored duration. No additional hour is added. Device time is used only for scheduling and refetch timers; it never grants completion permission. Fresh server `canMarkCompleted` controls the in-app action. Existing backend tests verify the inclusive exact boundary.

10. **Device behavior.** Android target SDK 36 was verified in the built APK, together with `POST_NOTIFICATIONS`, boot permission, and scheduled-notification receivers. Android and iOS permissions are requested once, when a future qualifying reminder exists; iOS initialization defers its permission prompt. Android uses `inexactAllowWhileIdle` for this informational reminder. The OS may delay delivery. A persisted allocation and OS pending-request payload prevent duplicate scheduling across restarts. The earliest 60 future reminders are retained to leave room below iOS's pending-notification limit. Notification taps validate the owner payload, refetch the viewing through the guarded API, and open existing Viewing Details.

11. **In-app fallback.** Works independently of device permission or plugin failures. A fresh Approved viewing with server permission shows `How did the viewing go?`, property, tenant, scheduled time, `Yes, mark completed`, and `Not now`. Prompts wait until the root route is settled, avoiding details/forms/dialogs. Only one prompt is shown per activation; no dialogs are chained. A ten-minute per-viewing cooldown limits repeated prompts on short resumes. Refetch timers track all already-checked timestamps to prevent polling loops when the device clock is ahead. Yes calls the existing completion endpoint. A 409 refreshes the viewing, shows the server message, and offers no optimistic completion. Not now only closes the dialog.

12. **Tenant follow-up/review reuse.** Existing server claim/response flow is preserved. Eligibility remains Completed viewing plus the existing duration-and-60-minute rule, evaluated by server time. Claims retain the existing ten-minute lease, unique viewing record, and response idempotency. Optional review uses the existing Completed-viewing review editor, validation, and API. Apply now and Not now retain the existing decision/application journey. The existing root host checks at startup/resume and avoids chaining prompts.

13. **Tenant device reminder.** Not added. The existing contract exposes a claimable follow-up and lease, rather than a future authoritative scheduling timestamp. Its in-app prompt remains active. Scheduling a tenant reminder would require a separate server contract; no local eligibility time was invented.

14. **Applications scope.** Connected all owned-property application lists through the existing APIs. Added only display summaries (`propertyTitle`, `applicantName`) to the existing response, populated from related records without contact details. Lists show real names, property, status, and submitted/updated timestamps. Details retain the financial/application summary, existing document access, landlord response, and already-implemented review/decision actions. No web-parity workflows were added. Existing role authorization remains in place.

15. **Files changed.**

   Backend:
   - `backend/RentFlow.Api/DTOs/Viewings/ViewingResponseDto.cs`
   - `backend/RentFlow.Api/Services/ViewingService.cs`
   - `backend/RentFlow.Api/DTOs/RentalApplications/RentalApplicationResponseDto.cs`
   - `backend/RentFlow.Api/Services/RentalApplicationService.cs`
   - `backend/RentFlow.Api.Tests/Services/LandlordWorkspaceDisplayTests.cs`

   Mobile application:
   - `mobile/rentflow_mobile/lib/main.dart`
   - `mobile/rentflow_mobile/lib/shared/home/landlord_home.dart`
   - `mobile/rentflow_mobile/lib/shared/home/tenant_home.dart`
   - `mobile/rentflow_mobile/lib/shared/home/home_greeting.dart`
   - `mobile/rentflow_mobile/lib/shared/home/landlord_workspace_service.dart`
   - `mobile/rentflow_mobile/lib/shared/shell/shared_app_shell.dart`
   - `mobile/rentflow_mobile/lib/features/properties/services/property_api_service.dart`
   - `mobile/rentflow_mobile/lib/features/viewings/models/viewing.dart`
   - `mobile/rentflow_mobile/lib/features/viewings/services/viewing_api_service.dart`
   - `mobile/rentflow_mobile/lib/features/viewings/services/viewing_reminders.dart`
   - `mobile/rentflow_mobile/lib/features/viewings/services/local_reminder_device.dart`
   - `mobile/rentflow_mobile/lib/features/viewings/widgets/landlord_reminder_host.dart`
   - `mobile/rentflow_mobile/lib/features/viewings/widgets/landlord_completion_dialog.dart`
   - `mobile/rentflow_mobile/lib/features/viewings/screens/landlord_viewing_requests_screen.dart`
   - `mobile/rentflow_mobile/lib/features/viewings/screens/landlord_viewing_request_details_screen.dart`
   - `mobile/rentflow_mobile/lib/features/rental_applications/models/rental_application.dart`
   - `mobile/rentflow_mobile/lib/features/rental_applications/screens/landlord_rental_applications_screen.dart`
   - `mobile/rentflow_mobile/lib/features/rental_applications/screens/landlord_rental_application_details_screen.dart`

   Platform/dependencies:
   - `mobile/rentflow_mobile/pubspec.yaml` and `pubspec.lock`
   - `mobile/rentflow_mobile/android/app/src/main/AndroidManifest.xml`
   - `mobile/rentflow_mobile/android/app/src/main/res/drawable/ic_viewing_reminder.xml`
   - `mobile/rentflow_mobile/ios/Runner/AppDelegate.swift`
   - Generated plugin additions in `macos/Flutter/GeneratedPluginRegistrant.swift` and `windows/flutter/generated_plugins.cmake`

   Tests:
   - `mobile/rentflow_mobile/test/helpers/landlord_workspace_fixture.dart`
   - `mobile/rentflow_mobile/test/landlord_home_test.dart`
   - `mobile/rentflow_mobile/test/viewing_reminders_test.dart`
   - `mobile/rentflow_mobile/test/local_reminder_device_test.dart`
   - `mobile/rentflow_mobile/test/landlord_reminder_host_test.dart`
   - `mobile/rentflow_mobile/test/landlord_workspace_lists_test.dart`
   - Updated `landlord_viewing_requests_test.dart`, `landlord_application_review_test.dart`, and `shared_shell_test.dart`

   This report: `docs/landlord-mobile-lite-implementation-report.md`. Existing unrelated generated-plugin/pytest changes were preserved. No web changes or database migrations were needed.

16. **Focused Flutter tests.** 229 passed, exit code 0. Covers Home/greeting/actions/activity/bell, 320 logical pixels, 720×1560 at 2× density, 1080×2340 at 3× density, and each at 200% text; owner-scoped list loading and correct detail navigation; empty/error/retry/partial-fetch states; viewing detail/contact/completion regressions; reminder scheduling, persistence, rescheduling, cancellation, ownership, denied permission, adapter UTC serialization, iOS deferred permission, Not now, real completion calls, 409 recovery, one prompt at a time, multiple expired timestamps without repeated polling, notification tap navigation; Tenant follow-up and review/details regressions.

17. **Full Flutter suite.** 1,308 passed, exit code 0 after the final code review fixes.

18. **Backend validation.** Focused viewing/follow-up/application suite: 219 passed, 8 PostgreSQL-dependent tests skipped. Full suite including new display-summary tests: 969 passed, 16 environment-dependent tests skipped, 0 failed, exit code 0. No viewing/application business rules changed.

19. **Analyze/APK.** `flutter analyze --no-pub`: no issues, exit code 0. Debug APK built successfully with exit code 0: `mobile/rentflow_mobile/build/app/outputs/flutter-apk/app-debug.apk`. The merged APK manifest was checked for target SDK and notification permissions/receivers. iOS platform calls were tested with the registered adapter and mocked native channel; an iOS build/device run was not available on Windows.

20. **Diff check.** `git diff --check` returned exit code 0. A separate backend/mobile scope check also passed. The whole-repository command emitted access warnings for pre-existing pytest temporary artifacts and line-ending notices; no whitespace errors were reported in the implementation.

21. **Remaining limits.** Physical-device notification delivery, reboot behavior, and iOS compilation have not been exercised here. OS battery/notification settings can suppress or delay delivery. Remote cancellation or schedule changes while the app is closed are reconciled on the next successful startup/resume fetch; no push infrastructure was added. Reconciliation requires API access and intentionally never treats a failed/partial fetch as an empty collection. More than 60 upcoming reminders are filled in as earlier reminders leave the scheduling window. PostgreSQL-only tests need the repository's configured test database. Tenant device reminders remain optional and unimplemented for the contract reason above.

Validation logs and backend TRX results are under `.tmp/landlord-validation/`.
