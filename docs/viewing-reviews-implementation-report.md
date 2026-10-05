# Task 5 — Verified viewing reviews

Implemented on `feature/mobile-ui-redesign`. No branch operations, commit, push, or PR. Review submission is implemented in Flutter; React provides public display.

1. **Eligibility:** Only an authenticated Tenant who owns a `ViewingRequest` with `Status == Completed` can create or edit its review. Other tenants receive 404; other roles receive 403; anonymous callers receive 401. Pending, Approved, Cancelled, and Rejected cannot be reviewed. The review has no dependency on an active follow-up, its one-hour threshold, or its decision.

2. **Model:** Dedicated `ViewingReview` with `Id`, unique `ViewingId`, `TenantId`, `PropertyId`, `LandlordId`, integer `PropertyRating`/`LandlordRating`, optional `Comment`, `CreatedAt`, and `UpdatedAt`. It is separate from `ViewingFollowUp`. Each genuinely separate Completed viewing can have one review, including multiple viewings of the same property.

3. **Migration:** Additive `20261004093254_AddViewingReviews` creates the table, unique viewing index, property/date and landlord/date indexes, tenant index, four foreign keys, and a 1–5 range CHECK for both ratings. Comment is nullable `varchar(500)`. Viewing/property/tenant deletion follows existing cascade conventions; historical landlord deletion is restricted while reviews reference it. The generated SQL adds no historical reviews and makes no destructive changes. Task 4/4.1 migrations were untouched. Migration was tested only in disposable PostgreSQL schemas; application database deployment remains pending.

4. **API:** Tenant-only `PUT /api/viewings/{viewingId}/review` creates or updates the same row, returns 200, preserves `CreatedAt`, and advances `UpdatedAt` from server `TimeProvider`. JWT supplies tenant identity; the viewing and property supply association IDs on first creation. Request DTO has only ratings/comment. The viewing row is locked with PostgreSQL `FOR UPDATE` inside a transaction, serializing competing initial inserts and edits. Existing tracked rows are reloaded under the lock. Tenant-only `GET` on the same route returns the owner's review, 204 if absent, or 404 for an unowned/missing viewing.

5. **Validation:** Both ratings are required integers from 1 through 5. Decimal values, strings, missing values, and out-of-range values are rejected. Validation exists in the DTO and service, with range enforcement also in PostgreSQL. Comments are optional, limited to 500 characters, trimmed, and normalized to null when blank.

6. **Follow-up:** Added olive star selectors and optional comment input to the existing scrollable cream dialog. Any entered rating/comment requires both ratings. Review PUT must succeed before the existing follow-up response POST; closing/navigation follows confirmed decision persistence. Review-save failure keeps entered input and the dialog available. A successfully saved unchanged review is skipped on a subsequent decision retry. A lost review acknowledgement can safely retry the same viewing-scoped PUT. Apply still resolves fresh application eligibility before routing.

7. **No review:** Untouched empty fields skip review PUT and use the normal Apply/NotNow flow. Partial input is not silently discarded: validation explains the requirement, and Clear review lets the tenant continue without creating a review. A review-load failure offers Retry review while still allowing an untouched optional review to be skipped.

8. **Existing review:** Opening the follow-up fetches the tenant's own review. An existing review displays a compact “Your viewing review is already saved” summary with an Edit option. Editing prefills both ratings and comment and updates the same resource. Leaving it unchanged does not PUT another review. The Apply/NotNow question stays separate.

9. **Completed Viewing Details:** Added a review card alongside the existing application next step. No review offers Leave a review; a saved review shows property/landlord stars and comment with Edit review. A compact scrollable sheet saves before closing and refreshes the card. The review workflow defers lifecycle prompts while open. Non-Completed viewing screens have no review action.

10. **Property display:** Anonymous `GET /api/properties/{propertyId}/viewing-reviews` aggregates only stored review rows using `PropertyRating`. It returns actual count, average rounded to one decimal, and up to five recent nonblank written reviews ordered by creation time and ID. Zero reviews returns null average and an empty list. Flutter and React omit the section for zero reviews or an unavailable response; neither fabricates 0.0 ratings. Real summaries use “Viewing experience” and “verified viewings.” Existing booking/application CTAs remain.

11. **Landlord display:** Anonymous `GET /api/properties/{propertyId}/landlord-viewing-reviews` resolves the landlord through the existing property-scoped public-profile architecture, respecting active landlord/role rules. It aggregates `LandlordRating` across all reviews whose stored historical `LandlordId` matches, including multiple properties. Both clients show “Landlord experience,” real counts/average, and recent viewing comments alongside the existing identity, public contact, and listings. No generic public user endpoint was added.

12. **Privacy:** Public summary DTO contains only `averageRating`, `reviewCount`, and `reviews`. A public review contains only `rating`, `comment`, and `reviewMonth` (`yyyy-MM`). No tenant ID/name/email/phone/avatar, viewing ID, application information, or precise attendance timestamp is returned. Clients render explicit allowed fields even when tests send unsupported private fields. Comments use normal escaped text rendering.

13. **Verification:** “Verified viewing” represents the backend's enforced Completed status plus viewing-tenant ownership. No verification badge from unrelated account/profile fields, fake reviews, tenancy claims, or “Verified tenant” wording was added.

14. **Historical attribution:** First PUT captures `PropertyId` from the viewing and `LandlordId` from the authoritative property at review creation. Subsequent edits preserve both. If ownership changes afterward, the review remains in that property's aggregate and the original landlord's historical aggregate; it does not become feedback about the new owner. Service and PostgreSQL tests exercise ownership transfer and same-row edits.

15. **Application eligibility:** Unchanged. Review presence, review scores, and NotNow do not alter the Completed-viewing application prerequisite. Tests verify eligibility with a low score, review editing, and a persisted NotNow response. No application is automatically created by a review or follow-up choice.

16. **Task 4.1 leases:** Unchanged. Ten-minute server lease, inclusive expiry recovery, same-row reclaim, tenant locking, permanent `RespondedAt`, idempotent/conflicting decisions, and acceptance of late responses remain. Review PUT neither claims nor finishes a follow-up. Existing lease tests ran in regression and full backend suites.

17. **Files:** Complete inventory below: 30 files including this report.

18. **Backend validation:** Restore and Release build passed; build had zero warnings/errors. Focused review tests: **25 passed**, no skips. Viewing/application eligibility regression filter: **214 passed**, no skips. Full backend suite: **913 passed**, no skips. Tests cover statuses, JWT/roles/ownership, integer JSON validation, comments, uniqueness/edits/timestamps, aggregates and bounded ordered comments, privacy, attribution, and application/follow-up independence. The local running Debug API held its executable open, so migration generation used Release without stopping that existing process.

19. **PostgreSQL:** Focused review integration passed on PostgreSQL 18.4 in an isolated disposable schema. Two PUTs blocked on the real viewing row lock, then both completed with the same review ID and one row. Unique viewing and rating CHECK violations were verified at database level; editing after ownership transfer preserved the original landlord and creation timestamp. Public aggregates were queried through Npgsql. Existing PostgreSQL viewing/application/lease regressions also passed in the full suite. The disposable test server was stopped afterward.

20. **Flutter validation:** Focused review/follow-up/details/profile group: **129 passed**. Full suite: **780 passed**. It covers optional/partial review input, save order, failure preservation and safe retry, existing review editing, application routing, independent Completed Viewing Details submission/edit, non-Completed exclusion, true public summaries and no fake zero ratings, identity omission, and long comments at 320 pixels/2x text.

21. **React validation:** ESLint passed. Focused Property Details/Landlord Profile tests: **39 passed**. Full React suite: **552 passed**, 52 files. Production build passed. Tests cover actual average/count, verified comments, empty states, private-field omission, and existing contact/listing behavior. Vite emitted its existing large-chunk warning.

22. **Final checks:** EF reports no pending model changes. Generated migration SQL was inspected for unique index, foreign keys, nullable comment/length, indexes, and range CHECK. Flutter analyze reported no issues. Debug APK built at `mobile/rentflow_mobile/build/app/outputs/flutter-apk/app-debug.apk`. Scoped and full `git diff --check` passed; the full check emits permission diagnostics for pre-existing inaccessible agent pytest temporary files, which this task did not modify. Gradle emitted its existing Java native-access warning; Vite emitted its large-chunk warning. Restore/Release build and React production build passed.

23. **Remaining limits:** Applying the migration with backend deployment is required. No deployed-environment or physical-device walkthrough was performed. Public display is limited to five recent written reviews, without an infinite browser. React review submission, deletion, replies, moderation/reporting, notifications, filters, and sentiment features are outside this task. Historical landlord feedback is accessed through an existing property anchor for that landlord; no generic user lookup was introduced. The established bundle-size warning remains.

File inventory:

| File | Purpose |
| --- | --- |
| `backend/RentFlow.Api/Models/ViewingReview.cs` | Dedicated review entity |
| `backend/RentFlow.Api/DTOs/ViewingReviews/ViewingReviewDto.cs` | Validated input, own review, safe public contracts |
| `backend/RentFlow.Api/Services/ViewingReviewService.cs` | Ownership, serialized upsert, snapshots, aggregate queries |
| `backend/RentFlow.Api/Controllers/ViewingReviewsController.cs` | Own GET/PUT and property-scoped public GETs |
| `backend/RentFlow.Api/Data/ApplicationDbContext.cs` | Table, keys, foreign keys, indexes, CHECK |
| `backend/RentFlow.Api/Program.cs` | Service registration |
| `backend/RentFlow.Api/Data/Migrations/20261004093254_AddViewingReviews.cs` | Additive migration |
| `backend/RentFlow.Api/Data/Migrations/20261004093254_AddViewingReviews.Designer.cs` | Generated migration metadata |
| `backend/RentFlow.Api/Data/Migrations/ApplicationDbContextModelSnapshot.cs` | Review model snapshot |
| `backend/RentFlow.Api.Tests/Services/ViewingReviewTests.cs` | Review domain, aggregates, snapshots, regression coverage |
| `backend/RentFlow.Api.Tests/Authentication/ViewingReviewEndpointsTests.cs` | JSON/authorization/privacy contracts |
| `backend/RentFlow.Api.Tests/Data/ViewingPostgresTests.cs` | Serialized PUT, constraints, attribution |
| `mobile/rentflow_mobile/lib/features/viewing_reviews/services/viewing_review_api_service.dart` | Models and review API access |
| `mobile/rentflow_mobile/lib/features/viewing_reviews/widgets/viewing_review_editor.dart` | Shared stars/comment editor and existing-review summary |
| `mobile/rentflow_mobile/lib/features/viewing_reviews/widgets/own_viewing_review_card.dart` | Completed-viewing card/sheet |
| `mobile/rentflow_mobile/lib/features/viewing_reviews/widgets/public_viewing_reviews.dart` | Safe compact public summary |
| `mobile/rentflow_mobile/lib/features/viewing_follow_ups/widgets/viewing_follow_up_dialog.dart` | Optional review and ordered persistence |
| `mobile/rentflow_mobile/lib/features/viewings/screens/tenant_viewing_details_screen.dart` | Completed-only review integration |
| `mobile/rentflow_mobile/lib/features/properties/screens/property_details_screen.dart` | Public property review integration |
| `mobile/rentflow_mobile/lib/features/properties/screens/public_landlord_profile_screen.dart` | Public landlord review integration |
| `mobile/rentflow_mobile/test/viewing_follow_up_test.dart` | Review flow tests and scroll-aware interaction |
| `mobile/rentflow_mobile/test/tenant_viewing_details_screen_test.dart` | Review create/edit and status exclusion |
| `mobile/rentflow_mobile/test/viewing_reviews_public_test.dart` | Public real/empty summaries, privacy, scaled layout |
| `web/rentflow-web/src/features/properties/components/ViewingReviews.jsx` | Shared public display |
| `web/rentflow-web/src/features/properties/components/viewing-reviews.css` | Compact olive/cream review styling |
| `web/rentflow-web/src/features/properties/pages/PropertyDetailsPage.jsx` | Property review section |
| `web/rentflow-web/src/features/properties/pages/PublicLandlordProfilePage.jsx` | Landlord review section |
| `web/rentflow-web/src/features/properties/pages/PropertyDetailsPage.test.jsx` | Aggregate/empty/privacy coverage |
| `web/rentflow-web/src/features/properties/pages/PublicLandlordProfilePage.test.jsx` | Landlord aggregate/empty/privacy coverage |
| `docs/viewing-reviews-implementation-report.md` | This report |

SQL and validation logs are local artifacts under ignored `.tmp/task5-*` paths.
