# Task 5.1 — Ratings and review visibility

Implemented on `feature/mobile-ui-redesign`, confirmed before editing and again during validation. No branch operations, commit, push, or PR.

1. **Property rating placement:** Flutter places a compact property aggregate immediately below rent and before the facts. React places it below rent in Rental summary for tenants. Each uses the property aggregate, never the landlord average. Zero counts, failures, and pending summaries render no compact rating. The accessible rating action scrolls to Viewing experience; web also focuses that section.

2. **Listed by rating:** Both clients place a secondary landlord aggregate below member-since and above the existing profile link. It uses only the landlord aggregate and disappears independently when that landlord has no feedback. Identity and contact behavior remain intact.

3. **Property Viewing experience:** Shared display components provide an 18-point heading, 20-point average, 13-point verified-viewing count, integer review stars, 14-point comments, and 12-point verification/month labels. Written comments only, at most five; ratings without comments still count in the backend aggregate. Singular wording is `1 verified viewing`.

4. **Public landlord experience:** The existing profile screen/page automatically uses the polished shared display with landlord-specific ratings and recent comments. Existing identity → contact → landlord experience → other properties ordering remains. Public profile and property cards/navigation are preserved.

5. **Landlord own visibility:** Flutter Profile → Reviews opens a compact read-only screen. React adds Reviews to the existing landlord menu at `/modules/reviews`, protected for Landlord only. Both show historical overall landlord feedback and feedback grouped by currently owned properties, including unrated properties. The global empty state says `No viewing feedback yet` and explains when verified feedback appears. Failed reads offer retry instead of reporting an empty history.

6. **Landlord permissions:** No editable rating controls or Delete/Hide/Edit review actions exist in these displays. The new controller exposes GET only. Endpoint tests reject PUT/DELETE; non-landlord roles get 403 and anonymous callers get 401. Existing tenant author review editing remains unchanged.

7. **Backend change and reason:** Added `GET /api/landlord/viewing-reviews/summary`. Existing public endpoints require a current property as the landlord anchor, so they cannot expose the owner's historical landlord aggregate after all properties transfer away. They also require one summary call per owned property to build a grouping. The new endpoint takes identity exclusively from JWT and makes one bounded database projection for owned property groups, plus the existing landlord summary queries. No schema/migration/model changes. Public summary logic is reused without changing the public contract.

8. **Historical attribution:** Overall landlord feedback filters the immutable review-creation `LandlordId` snapshot. Property groups filter review `PropertyId` against current ownership. After a transfer, property feedback remains with the property, old landlord feedback remains with the original landlord, and the new landlord inherits no landlord rating. Service, HTTP scope, and real PostgreSQL tests cover this behavior, including a former owner with no remaining properties.

9. **Privacy and performance:** Review DTOs contain only relevant rating, written comment, and safe `yyyy-MM` month. Owner group metadata adds property ID/title, never tenant or viewing IDs, names, contacts, application status, or exact timestamps. Both clients render explicit safe fields and ignore private extras. Property Details reuses one response per rating dimension between compact/full displays. The owner page makes one HTTP request. No discovery-card rating requests were added.

10. **Files changed:** Listed below. Public profile production files did not require changes because they already consume the shared public review component. Task 4/4.1 follow-up logic, review submission/eligibility, viewing completion, and application eligibility files are untouched.

11. **Backend verification:** Restore passed; Release API build passed with zero warnings/errors; focused ViewingReview tests **29 passed, 0 skipped**; full suite **917 passed, 0 skipped**. PostgreSQL component tests ran against the disposable local database, including owner summary projection, concurrency, historical snapshots, and constraints. EF `has-pending-model-changes` reported none. Disposable PostgreSQL stopped after testing; no application database migration was performed.

12. **Flutter verification:** Focused property details/public landlord/public review/owner review/profile tests **54 passed**. Full suite **785 passed**. Coverage includes distinct aggregates, zero omission, singular wording, one request per dimension, accessible rating tap/scroll, written-comment filtering, identity privacy, readonly owner screen, retry, and 320px width with 2× text. Analyze passed with no issues.

13. **React verification:** Focused Property Details/Public Landlord Profile/Landlord Reviews/shell tests **77 passed**. Full suite **557 passed in 53 files**. Coverage includes distinct property/landlord placement, independent zero omission, singular wording, keyboard-compatible rating action and focus, anonymous comments, read-only owner view, retry/empty states, bearer authentication, and role-protected navigation.

14. **Builds and diff:** ESLint passed. React production build passed with the existing warning about a minified chunk over 500kB. Flutter debug APK build passed: `mobile/rentflow_mobile/build/app/outputs/flutter-apk/app-debug.apk` (37.2s Gradle build; existing JVM native-access tooling warning). Scoped Task 5.1 `git diff --check` passed. The full-workspace check exited 0 with permission warnings for pre-existing inaccessible `agent/.pytest_tmp_asus/*current` files; those were not modified by this task.

15. **Limitations:** Recent written comments remain bounded to five per aggregate/property, with no all-history pagination. Owner grouping lists currently owned properties; historical landlord feedback remains visible separately even after property transfer. No moderation/report/removal workflow was added. Physical-device and live deployed API visual checks were not performed; responsive Flutter widget tests and React DOM tests passed. The existing Task 5 migration remains a deployment prerequisite; Task 5.1 adds none.

## File inventory

| File | Purpose |
| --- | --- |
| `backend/RentFlow.Api/Controllers/LandlordViewingReviewsController.cs` | JWT-scoped landlord-only GET |
| `backend/RentFlow.Api/DTOs/ViewingReviews/ViewingReviewDto.cs` | Safe owner summary/group DTOs |
| `backend/RentFlow.Api/Services/ViewingReviewService.cs` | Shared summary logic and bounded owner grouping |
| `backend/RentFlow.Api.Tests/Authentication/ViewingReviewEndpointsTests.cs` | Role, scope, privacy, read-only HTTP tests |
| `backend/RentFlow.Api.Tests/Services/ViewingReviewTests.cs` | Grouping, dimensions, historical ownership |
| `backend/RentFlow.Api.Tests/Data/ViewingPostgresTests.cs` | PostgreSQL owner projection and snapshot checks |
| `mobile/rentflow_mobile/lib/features/properties/screens/property_details_screen.dart` | Compact placements, shared futures, scroll action |
| `mobile/rentflow_mobile/lib/features/viewing_reviews/services/viewing_review_api_service.dart` | Owner GET and shared validation |
| `mobile/rentflow_mobile/lib/features/viewing_reviews/widgets/public_viewing_reviews.dart` | Reusable public loader/display |
| `mobile/rentflow_mobile/lib/features/viewing_reviews/widgets/viewing_rating_summary.dart` | Compact accessible rating/full readonly summary |
| `mobile/rentflow_mobile/lib/features/viewing_reviews/screens/landlord_reviews_screen.dart` | Owner Reviews screen |
| `mobile/rentflow_mobile/lib/shared/profile/shared_profile_content.dart` | Landlord Profile Reviews entry |
| `mobile/rentflow_mobile/lib/shared/shell/shared_app_shell.dart` | Reviews screen navigation/service wiring |
| `mobile/rentflow_mobile/test/viewing_reviews_public_test.dart` | Public ratings, tap, scale, privacy tests |
| `mobile/rentflow_mobile/test/landlord_reviews_screen_test.dart` | Owner readonly/empty/failure/scaling tests |
| `mobile/rentflow_mobile/test/shared_profile_test.dart` | Landlord-only Reviews entry/action tests |
| `web/rentflow-web/src/App.jsx` | Protected landlord Reviews route |
| `web/rentflow-web/src/features/properties/useViewingReviews.js` | Shared public loading and validation |
| `web/rentflow-web/src/features/properties/components/ViewingReviews.jsx` | Compact/full readonly review components |
| `web/rentflow-web/src/features/properties/components/viewing-reviews.css` | Restrained hierarchy and compact styles |
| `web/rentflow-web/src/features/properties/pages/PropertyDetailsPage.jsx` | Compact placements and scroll/focus action |
| `web/rentflow-web/src/features/properties/pages/LandlordReviewsPage.jsx` | Owner feedback page |
| `web/rentflow-web/src/features/properties/pages/PropertyDetailsPage.test.jsx` | Placement, dimensional/empty/privacy/action tests |
| `web/rentflow-web/src/features/properties/pages/PublicLandlordProfilePage.test.jsx` | Accessible polished aggregate assertion |
| `web/rentflow-web/src/features/properties/pages/LandlordReviewsPage.test.jsx` | Owner readonly/empty/failure/privacy tests |
| `web/rentflow-web/src/shared/navigation/roleNavigation.js` | Landlord Reviews navigation item |
| `web/rentflow-web/src/shared/layout/AppShell.jsx` | Reviews menu icon |
| `web/rentflow-web/src/shared/ui/Icons.jsx` | Star icon in the existing icon system |
| `web/rentflow-web/src/shared/shell.test.jsx` | Navigation and owner role guard tests |
| `docs/viewing-review-visibility-report.md` | Task 5.1 report |
