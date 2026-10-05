# Task 4.1 — Recoverable viewing follow-up claims

Implemented on `feature/mobile-ui-redesign`. No branch operation, commit, push, or PR was performed.

1. **Previous failure:** Task 4 excluded every viewing with an existing follow-up row. If the claim committed but its HTTP response was lost, or the app terminated before the tenant answered, that unresolved row permanently consumed the automatic prompt.

2. **Lease duration:** Ten minutes, centralized in `ViewingFollowUpService.ClaimLeaseDuration`. The injected server `TimeProvider` determines both timestamps after acquiring the tenant lock. The claim DTO now includes `ClaimExpiresAt` for diagnostics; Flutter does not use it to decide eligibility.

3. **Claim eligibility:** The JWT tenant must own a Completed viewing with a real property, and server time must be at or after its stored scheduled end plus one hour. A never-claimed viewing is available. An existing row is available only for its owner when `RespondedAt` is null and the expiry is null (legacy) or `serverNow >= ClaimExpiresAt`. An active lease or any recorded response excludes that viewing. Exactly expiry qualifies; one tick before does not. Selection orders all available viewings, including recoverable ones, by their scheduled end plus one hour, then ID, and returns at most one per request. Application eligibility and viewing completion rules were not changed.

4. **Reclaim:** The same row, follow-up ID, viewing ID, and tenant ID are reused. `ClaimedAt` and `ClaimExpiresAt` are renewed from server time; `Decision` and `RespondedAt` remain unset. No duplicate row is inserted. An older expired/legacy claim takes priority over newer eligible unclaimed viewings.

5. **Concurrent devices:** Claim and response still acquire the PostgreSQL tenant user row with `FOR UPDATE` inside a transaction. Selection happens after the lock. Concurrent reclaims for the same viewing yield one renewed lease; the other request gets 204 when no other viewing is available. The unique `ViewingId` index remains a second database safeguard. Existing tracked rows are reloaded under the lock before renewal to preserve updates from other connections. No distributed lock was introduced.

6. **Late responses:** Expiry controls claiming only. An authenticated owner can still explicitly answer an unresolved follow-up after expiry, including after another device has renewed it. Response operations remain serialized. Same-decision retries return the original response timestamp; a different decision returns 409. Either `ApplyNow` or `NotNow` permanently finishes the follow-up, regardless of subsequent expiry.

7. **Migration strategy:** Added `20261004083811_AddViewingFollowUpClaimLease`; did not rewrite `20261004075004_AddViewingFollowUps`. Although the historical Task 4 report records no application database deployment at that time, the original migration is now committed in `1329288` (`feat: Implement viewing follow-up feature with API integration`). It is no longer an uncommitted migration, and shared deployment state was not independently established. Preserving committed history with an additive upgrade safely supports both existing databases and fresh installations. This is one nullable `timestamp with time zone` column, with no default or data rewrite. No application/shared database migration was applied in this task.

8. **Legacy rows:** Existing rows receive null expiry. An unresolved null-expiry row is immediately recoverable and gets a real ten-minute lease on reclaim. Responded legacy rows remain finished, with their decisions/timestamps intact. No decisions were invented. A PostgreSQL upgrade test inserts both kinds of row using the old schema, applies the new migration, and verifies preservation and recovery.

9. **Flutter lifecycle:** The existing authenticated Tenant open/resume claim flow is unchanged. It requires no local recovery state, expiry arithmetic, countdown, polling, or automatic dismissal. A dialog remains usable beyond the lease. At most one dialog is active, checks do not overlap, and responses do not immediately chain to another prompt. Non-Tenant roles still do not claim. Claim failures remain quiet and retry only on a later normal check. Response failures retain the dialog and retry feedback; Apply navigation still waits for a valid persisted response and refreshed application eligibility. A confirmed 409 displays that another device already answered and offers Close, with no fabricated saved decision or application navigation.

10. **Scope:** No ratings, reviews, comments, new follow-up decisions, notifications, reminders, application business changes, or automatic viewing completion were added. JWT ownership checks remain authoritative.

11. **Changed files:** Fourteen files; complete inventory below. The existing Task 4 report now links to this report to identify its historical claim semantics.

12. **Backend tests:** Focused follow-up tests: **29 passed**, zero skipped. Viewing/application eligibility regression filter: **189 passed**, zero skipped. Full backend suite: **888 passed**, zero skipped. Coverage includes fresh expiry persistence, active leases, tick boundaries, same-row renewal, priority, both permanent decisions, late response/idempotency/conflict, legacy rows, role/JWT/ownership, and the existing end-plus-one-hour and completion/application tests.

13. **PostgreSQL:** Both focused follow-up integration tests passed against PostgreSQL 18.4 in isolated disposable schemas: concurrent initial claim and reclaim (with both connections blocked on the real tenant lock), response after renewed lease expiry, competing conflicting responses, actual unique-index enforcement, and old-schema migration preservation/recovery. All PostgreSQL tests also ran in the full suite without skips. The local disposable test server was stopped afterward.

14. **Flutter tests:** Focused follow-up tests: **30 passed**. Follow-up/auth/lifecycle/application/completion regression group: **169 passed**. Full suite: **768 passed**. New tests simulate app termination with no answer, a fresh open during the active server lease, recovery of the same ID on later resume, repeated resumes with one dialog, eleven minutes passing without polling/dismissal, normal response submission, and safe conflicts for both actions. Existing persistence-before-close/navigation and refreshed eligibility tests remain green.

15. **Validation:** Backend restore passed. Final Release build passed with zero warnings/errors. Flutter analyze reported no issues. EF pending-model check passed. Generated SQL was inspected: only `ALTER TABLE "ViewingFollowUps" ADD "ClaimExpiresAt" timestamp with time zone`, plus migration history. Nullability/default match the legacy strategy; existing unique index, foreign keys, and decision/response check remain intact. Debug APK built successfully at `mobile/rentflow_mobile/build/app/outputs/flutter-apk/app-debug.apk` (Gradle emitted its existing Java native-access warning). Scoped and full `git diff --check` passed; the full check emits permission diagnostics for pre-existing inaccessible agent pytest temporary files outside this task's changes.

16. **Limits:** Applying the additive migration with backend deployment remains necessary. No deployed-environment or physical-device walkthrough was performed. Recovery waits for lease expiry and a later normal app open/resume; there is no periodic retry/reminder. An older open dialog may coexist with a new device's prompt after expiry; serialized response/idempotency/conflict rules resolve their choices. Database timestamps use PostgreSQL microsecond precision; in-memory/API tests also exercise .NET tick boundaries.

File inventory:

| File | Change |
| --- | --- |
| `backend/RentFlow.Api/Models/ViewingFollowUp.cs` | Nullable persisted lease expiry |
| `backend/RentFlow.Api/DTOs/ViewingFollowUps/ViewingFollowUpDto.cs` | Server expiry in claim response |
| `backend/RentFlow.Api/Services/ViewingFollowUpService.cs` | Central duration, expired/legacy selection, same-row renewal |
| `backend/RentFlow.Api/Data/Migrations/20261004083811_AddViewingFollowUpClaimLease.cs` | Additive nullable column |
| `backend/RentFlow.Api/Data/Migrations/20261004083811_AddViewingFollowUpClaimLease.Designer.cs` | Generated migration model |
| `backend/RentFlow.Api/Data/Migrations/ApplicationDbContextModelSnapshot.cs` | Expiry metadata |
| `backend/RentFlow.Api.Tests/Services/ViewingFollowUpTests.cs` | Lease boundaries, legacy recovery, permanent/late responses, priority |
| `backend/RentFlow.Api.Tests/Authentication/ViewingFollowUpEndpointsTests.cs` | JWT/time authority through reclaim and late response |
| `backend/RentFlow.Api.Tests/Data/ViewingPostgresTests.cs` | Concurrent reclaim and legacy upgrade preservation |
| `mobile/rentflow_mobile/lib/features/viewing_follow_ups/services/viewing_follow_up_api_service.dart` | Explicit confirmed response-conflict exception |
| `mobile/rentflow_mobile/lib/features/viewing_follow_ups/widgets/viewing_follow_up_dialog.dart` | Safe conflict feedback and Close action |
| `mobile/rentflow_mobile/test/viewing_follow_up_test.dart` | Recovery, long-open dialog, both response-conflict cases |
| `docs/viewing-follow-up-implementation-report.md` | Historical behavior supersession link |
| `docs/viewing-follow-up-lease-implementation-report.md` | This implementation and validation report |

Validation logs and migration SQL are in the ignored `.tmp/task41-*` files; they are local artifacts.
