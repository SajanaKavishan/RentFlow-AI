# Task 4 — One-time tenant viewing follow-up

Implemented on `feature/mobile-ui-redesign`. No branch operation, commit, push, or PR was performed. React was not changed.

1. **Eligibility:** The authenticated tenant's viewing must be Completed, and server `TimeProvider.GetUtcNow()` must be at or after `RequestedDateTime + DurationMinutes + 60 minutes`. The stored duration snapshot is used. Approved/Pending/Rejected/Cancelled viewings do not qualify, regardless of elapsed time. Late landlord completion can qualify immediately. Device time and formatted local strings do not determine eligibility.

2. **Persisted model:** `ViewingFollowUp` has `Id`, `ViewingId`, `TenantId`, `ClaimedAt`, nullable `Decision`, and nullable `RespondedAt`. Decisions use persisted strings `ApplyNow` and `NotNow`. Creating the row claims the automatic prompt. No separate local once-only tracker is used.

3. **Migration:** `20261004075004_AddViewingFollowUps` adds only the follow-up table, foreign keys to viewing/user, unique `ViewingId`, a tenant/claim-time index, and a constraint requiring a valid decision and response timestamp together. Existing viewings, applications, statuses, and decisions are not rewritten or backfilled. SQL was generated and inspected; the snapshot is updated and EF reports no pending changes. Migration testing used isolated disposable PostgreSQL schemas. The migration has not been applied to the application database; it must be applied with deployment of this backend.

4. **Claim strategy:** Tenant-only `POST /api/viewing-follow-ups/next/claim` derives identity from JWT, lazily finds the oldest eligible unclaimed Completed viewing with a real property, creates a claim, and returns safe context. No eligible viewing returns 204. Context contains follow-up/viewing IDs, server claim time, nullable recorded completion time, public property ID/title/address/city, and Task 3 application eligibility. Images use the existing property-image endpoints.

5. **Concurrency:** PostgreSQL transactions lock the authenticated tenant's user row before selecting or responding. Concurrent devices cannot claim the same viewing; the unique viewing index also enforces this at the database level. Responses are reloaded under the lock before mutation. Same-decision retries return the saved acknowledgement without changing its timestamp; conflicting responses return 409. Another tenant's or an unclaimed follow-up returns 404. Non-Tenant roles return 403 and anonymous requests return 401.

6. **Multiple viewings:** Ordering uses scheduled end plus one hour, with viewing ID as a stable tie-breaker. Each request claims at most one. The mobile host does not chain another dialog after a response. A later open/resume may claim the next viewing. Concurrent devices may claim different eligible viewings, while each individual viewing remains once-only.

7. **Not now:** The server saves NotNow and server RespondedAt before the dialog closes. It never automatically returns for that viewing. The Completed-viewing application policy and eligible-properties picker remain unaffected.

8. **Apply now:** The decision is confirmed first, then application eligibility is fetched again. The follow-up endpoint never creates an application. A permitted new application opens the existing wizard for the exact property, without an early POST. Changed availability/eligibility shows a truthful message and allows closing after the decision is saved.

9. **Existing applications:** The shared `applicationDestination` helper is used by both Task 3 Apply actions and the follow-up. It reloads eligibility and the actual existing application, validates its ID/property, and uses its fresh status. Draft/Changes Requested continue the same ID; other returned active statuses open details. Terminal/reapplication states follow existing backend eligibility rules.

10. **Lifecycle:** `MyApp` mounts `TenantFollowUpHost` above the root Navigator only after authenticated Tenant state resolves. It covers login, cold restoration, and resume on any tenant route. Authentication transitions reset the navigator/observer. Unresolved authentication, login, Landlord, Technician, and Admin screens do not claim. Checks are serialized. `FollowUpPause` protects application editing and document screens, including native picker resumes; dynamic guards protect submission on application list/details screens. Root modal and route-transition detection defer checks until safe.

11. **Popup:** A cream/olive, scrollable dialog displays How did your viewing go?, the real property image or existing fallback, real title/location, the application question, later-application helper, and explicit buttons. Font sizes are 21/16/14/13/15 for title/property/body/secondary/buttons. Narrow screens, long content, and 2x text scaling are tested.

12. **Dismissal:** Barrier taps and system Back do not dismiss the dialog. Not now explicitly persists the decision. Once ApplyNow is confirmed, a navigation failure can be retried or closed without pretending the decision was NotNow.

13. **Network failures:** Failed claims are quiet and leave the app usable; a later normal resume/open retries. Failed or malformed decision acknowledgements keep the dialog open with a concise retry message. Buttons are disabled while saving. The chosen decision stays fixed while its acknowledgement is uncertain, avoiding conflicting retries. Application navigation waits for a confirmed response. A saved ApplyNow is not reposted when only navigation needs retrying.

14. **Scope:** No ratings, reviews, comments, review aggregates, moderation, review badges, or automatic viewing completion were added. Task 3 creation/submission eligibility remains enforced.

15. **Files:** Complete inventory below: 26 implementation/test files plus this report.

16. **Backend validation:** Restore and Release build passed with zero build warnings/errors. Dedicated follow-up tests: 21 passed, including PostgreSQL boundary, concurrent claim/response, and actual unique-index enforcement. Viewing/application regression filter: 211 passed. Full suite: 880 passed, zero skipped. Existing completion and application gates remain green.

17. **Flutter validation:** Focused follow-up/auth/application/document/viewing regressions: 220 passed. Full suite: 764 passed. Coverage includes login/restoration/roles, other routes, background/foreground, modal/work deferral, busy scope changes, one-at-a-time prompts, errors/retry, fallback images, all requested application routes, stale eligibility, no early creation, and layout.

18. **Final checks:** Flutter analyze: no issues. Debug APK built at `mobile/rentflow_mobile/build/app/outputs/flutter-apk/app-debug.apk`. EF pending-model check passed and additive migration SQL was inspected. Full and scoped `git diff --check` returned success; the full check emitted permission diagnostics for pre-existing inaccessible agent pytest temporary files, which this task did not modify. The disposable PostgreSQL test server was stopped after validation.

19. **Limitations:** Claim-before-display provides at-most-once automatic prompting. If the claim commits but the response is lost, the app terminates, or the user logs out before display, that viewing will not automatically prompt again. A decision without a confirmed acknowledgement can be safely retried while the dialog remains open. Application/document editing screens conservatively defer prompts throughout the workflow. No physical-device or deployed-environment walkthrough was performed. Applying the additive migration to the application database remains a deployment step.

## File inventory

Backend:

- `backend/RentFlow.Api/Models/ViewingFollowUp.cs` (new)
- `backend/RentFlow.Api/DTOs/ViewingFollowUps/ViewingFollowUpDto.cs` (new)
- `backend/RentFlow.Api/Services/Interfaces/IViewingFollowUpService.cs` (new)
- `backend/RentFlow.Api/Services/ViewingFollowUpService.cs` (new)
- `backend/RentFlow.Api/Controllers/ViewingFollowUpsController.cs` (new)
- `backend/RentFlow.Api/Data/ApplicationDbContext.cs`
- `backend/RentFlow.Api/Data/Migrations/20261004075004_AddViewingFollowUps.cs` (new)
- `backend/RentFlow.Api/Data/Migrations/20261004075004_AddViewingFollowUps.Designer.cs` (new)
- `backend/RentFlow.Api/Data/Migrations/ApplicationDbContextModelSnapshot.cs`
- `backend/RentFlow.Api/Program.cs`
- `backend/RentFlow.Api.Tests/Services/ViewingFollowUpTests.cs` (new)
- `backend/RentFlow.Api.Tests/Authentication/ViewingFollowUpEndpointsTests.cs` (new)
- `backend/RentFlow.Api.Tests/Data/ViewingPostgresTests.cs`

Flutter:

- `mobile/rentflow_mobile/lib/main.dart`
- `mobile/rentflow_mobile/lib/shared/follow_up/follow_up_activity.dart` (new)
- `mobile/rentflow_mobile/lib/features/viewing_follow_ups/models/viewing_follow_up.dart` (new)
- `mobile/rentflow_mobile/lib/features/viewing_follow_ups/services/viewing_follow_up_api_service.dart` (new)
- `mobile/rentflow_mobile/lib/features/viewing_follow_ups/widgets/tenant_follow_up_host.dart` (new)
- `mobile/rentflow_mobile/lib/features/viewing_follow_ups/widgets/viewing_follow_up_dialog.dart` (new)
- `mobile/rentflow_mobile/lib/features/rental_applications/services/application_destination.dart` (new)
- `mobile/rentflow_mobile/lib/features/rental_applications/widgets/application_eligibility_action.dart`
- `mobile/rentflow_mobile/lib/features/rental_applications/screens/my_rental_applications_screen.dart`
- `mobile/rentflow_mobile/lib/features/rental_applications/screens/rental_application_details_screen.dart`
- `mobile/rentflow_mobile/lib/features/rental_applications/screens/rental_application_form_screen.dart`
- `mobile/rentflow_mobile/lib/features/application_documents/screens/application_documents_screen.dart`
- `mobile/rentflow_mobile/test/viewing_follow_up_test.dart` (new)

Report: `docs/viewing-follow-up-implementation-report.md` (new).
