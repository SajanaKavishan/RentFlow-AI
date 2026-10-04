# Task 3 — Completed viewing and rental application eligibility

Implemented on `feature/mobile-ui-redesign`. No commit, push, PR, or branch operation was performed.

1. **Final rule:** Any one Completed viewing belonging to the authenticated tenant for the exact property satisfies the viewing prerequisite. Pending, Approved, Rejected, Cancelled, another tenant's viewing, and another property's viewing do not qualify. There is no viewing expiry.

2. **Backend policy:** `RentalApplicationService` owns the reusable Completed-viewing query and business check. Identity comes from the JWT through `ICurrentUserService`; clients cannot supply eligibility identity.

3. **Creation:** New applications require an existing available property, no conflicting active application, valid application fields, and a qualifying viewing. Missing viewing eligibility returns 409 ProblemDetails with `Complete a viewing for this property before starting a rental application.` Property locking serializes competing creates; a PostgreSQL concurrency test confirms that only one draft is created.

4. **Submission:** Submit and resubmit check the same tenant/property prerequisite before changing status or sending a notification. Failed eligibility preserves the application's ID, data, status, and timestamps.

5. **Eligibility contract:** Tenant-only `GET /api/properties/{propertyId}/rental-application-eligibility` returns `canApply`, `hasCompletedViewing`, nullable `reason`, and nullable paired `existingApplicationId`/`existingApplicationStatus`. Only the current tenant's active application is returned. Missing property returns 404; anonymous access returns 401 and other roles return 403.

6. **Eligible properties:** Tenant-only `GET /api/rental-applications/eligible-properties` returns distinct available properties with Completed viewing history and no current active application. Each item contains `id`, `title`, `address`, `city`, and `monthlyRent`. Flutter loads real images through the existing property-image service, with the existing honest fallback.

7. **Existing applications:** Draft and Changes Requested continue with the same ID; Submitted and Under Review open existing details. Legacy drafts remain readable and editable before completion. Approved, Rejected, and Withdrawn retain the established reapplication policy: those statuses do not count as an active duplicate. Existing validation, document, ownership, and lifecycle checks remain in place.

8. **Flutter Property Details:** Eligibility is fetched from the backend. Apply is locked before completion, while checking, or on failure. Eligible properties open the existing wizard without creating an application early. Existing active applications show Continue/View. Refresh, resume, and return update eligibility; tapping rechecks for applications created on another device. Current unavailable property data also blocks new application navigation.

9. **Completed Viewing Details:** Completed viewings have an authoritative next-step card for the same property. Eligible tenants see Ready to apply? and Apply for this property; existing applications show Continue/View. Another business restriction hides the card. Other viewing statuses have no application card.

10. **My Applications + New:** Opens Choose a property using the eligible-properties endpoint. Arbitrary listings cannot enter this picker. Empty copy is No properties ready to apply / Complete a property viewing before starting a rental application, with Browse properties and My viewings destinations. Manual refresh, resume, and navigation return reload the picker.

11. **React:** Property Apply uses the same authoritative endpoint and displays locked eligibility or safe errors. Existing applications open the authorized detail page. Property-aware My Applications handoff explains eligibility and retains the existing mobile creation/editing workflow. Focus, visibility return, and My Applications manual refresh reload eligibility. No new web creation selector was introduced.

12. **Bypass protection:** Direct POST creation and PATCH submission are gated on the backend. Forged tenant IDs, client flags, and another tenant/property's history cannot confer eligibility. Flutter direct new-wizard entry checks eligibility, redirects to an existing application where applicable, and handles backend business messages safely.

13. **Database impact:** No model or migration changes. Existing Completed status, viewing ownership, property identity, and application status supply the policy. PostgreSQL validation used the disposable local test database, with isolated test schemas; the test server was stopped afterward.

14. **Files changed:** See the complete inventory below. Existing regression fixtures were updated to provide real Completed-viewing prerequisites or expect the new eligible picker and locked actions.

15. **Backend tests:** Focused eligibility/viewing/application/authorization/notification run: 229 passed, zero skipped. Full suite: 793 passed, zero skipped, including PostgreSQL query and competing-create validation.

16. **Flutter tests:** Focused property/viewing/application/wizard regression run: 275 passed. Final dedicated eligibility run: 24 passed. Full suite: 581 passed. Coverage includes legacy editing, same-ID continuation, no early POST, resume/return, another-device drafts, errors/retry, Completed cards, eligible picker, direct wizard entry, and small-screen large-text layout.

17. **React tests:** Focused Property Details and rental-application run: 61 passed. Full suite: 536 passed across 52 files using `--maxWorkers=2`. An earlier full run timed out in an unrelated property-form test under heavier concurrent load; the reduced-worker full run passed without changing that test or its timeout.

18. **Checks/builds:** Backend restore and Release build succeeded with zero build warnings/errors. EF reports no pending model changes. Flutter analyze reports no issues; debug APK built at `mobile/rentflow_mobile/build/app/outputs/flutter-apk/app-debug.apk`. ESLint and React production build passed. `git diff --check` returned success; scoped backend/mobile/web checks were also clean. The full Git check emitted permission diagnostics for pre-existing inaccessible agent pytest temporary files, which were not changed by this task.

19. **Limitations:** Web application creation/editing continues through the established mobile handoff. Validation used automated suites and local builds; no physical-device or deployed-environment walkthrough was performed. Vite retains its large-bundle warning. No popup, rating, review, prompt tracking, or automatic viewing completion was added.

## File inventory

Backend:

- `backend/RentFlow.Api/Controllers/RentalApplicationsController.cs`
- `backend/RentFlow.Api/DTOs/RentalApplications/RentalApplicationEligibilityDto.cs` (new)
- `backend/RentFlow.Api/Services/Interfaces/IRentalApplicationService.cs`
- `backend/RentFlow.Api/Services/RentalApplicationService.cs`
- `backend/RentFlow.Api.Tests/Authentication/RentalApplicationEligibilityEndpointsTests.cs` (new)
- `backend/RentFlow.Api.Tests/Services/RentalApplicationEligibilityTests.cs` (new)
- `backend/RentFlow.Api.Tests/Data/ViewingPostgresTests.cs`
- `backend/RentFlow.Api.Tests/Authentication/BusinessAuthorizationTests.cs`
- `backend/RentFlow.Api.Tests/Authentication/NotificationEventsTests.cs`
- `backend/RentFlow.Api.Tests/Services/RentalApplicationServiceTests.cs`

Flutter:

- `mobile/rentflow_mobile/lib/features/rental_applications/models/application_eligibility.dart` (new)
- `mobile/rentflow_mobile/lib/features/rental_applications/widgets/application_eligibility_action.dart` (new)
- `mobile/rentflow_mobile/lib/features/rental_applications/screens/eligible_application_properties_screen.dart` (new)
- `mobile/rentflow_mobile/lib/features/rental_applications/screens/my_rental_applications_screen.dart`
- `mobile/rentflow_mobile/lib/features/rental_applications/screens/rental_application_form_screen.dart`
- `mobile/rentflow_mobile/lib/features/rental_applications/services/rental_application_api_service.dart`
- `mobile/rentflow_mobile/lib/features/properties/screens/property_details_screen.dart`
- `mobile/rentflow_mobile/lib/features/viewings/screens/tenant_viewing_details_screen.dart`
- `mobile/rentflow_mobile/test/application_eligibility_test.dart` (new)
- `mobile/rentflow_mobile/test/helpers/discovery_backend.dart`
- `mobile/rentflow_mobile/test/property_availability_test.dart`
- `mobile/rentflow_mobile/test/property_details_test.dart`
- `mobile/rentflow_mobile/test/rental_application_ui_test.dart`
- `mobile/rentflow_mobile/test/tenant_application_journey_test.dart`

React:

- `web/rentflow-web/src/features/rentalApplications/useApplicationEligibility.js` (new)
- `web/rentflow-web/src/features/rentalApplications/services/rentalApplicationApiService.js`
- `web/rentflow-web/src/features/properties/pages/PropertyDetailsPage.jsx`
- `web/rentflow-web/src/features/properties/components/PropertyWorkflowHandoff.jsx`
- `web/rentflow-web/src/features/rentalApplications/pages/MyApplicationsPage.jsx`
- `web/rentflow-web/src/features/properties/pages/PropertyDetailsPage.test.jsx`
- `web/rentflow-web/src/features/rentalApplications/pages/MyApplicationsPage.test.jsx`
- `web/rentflow-web/src/features/rentalApplications/services/jwtContracts.test.js`

Report: `docs/completed-viewing-application-eligibility-report.md` (new).
