# Property viewing availability implementation

Implemented on the existing `feature/mobile-ui-redesign` branch. No commit, push, PR, branch change, or application-database migration was performed. Database migrations were exercised only against a disposable PostgreSQL test database.

## 1. Final availability data model

`PropertyViewingAvailability`: `Id`, `PropertyId`, numeric `DayOfWeek`, local `TimeOnly StartTime` and `EndTime`, and `IsEnabled`. At most one row per property/weekday. Disabled rows store cleared times and return null times in the API.

`Property`: `ViewingSlotDurationMinutes` and `ViewingTimeZoneId`. Settings default to 60 minutes and `Asia/Colombo`. The 60-minute setting is an explicit editor value, not a configured schedule: without saved enabled windows there are no slots.

`ViewingRequest`: non-null `DurationMinutes`, snapshotted from the current schedule during request creation. Existing request fields and statuses are preserved.

## 2. Migration details

`20261002075438_AddPropertyViewingAvailability` is additive. It adds the settings and request duration, creates the availability table with a cascading property FK, and adds a unique property/weekday index. Constraints validate weekday 0–6, enabled start before end, supported property durations, and positive request duration.

Viewing indexes cover `(PropertyId, Status, RequestedDateTime)`, `RequestedDateTime`, `Status`, and `(TenantId, PropertyId, RequestedDateTime)`. The tenant duplicate index is nonunique so historical duplicate data is not destructively altered; protected service writes enforce the existing duplicate rule.

The user explicitly approved backfilling **legacy duration only to 60 minutes**. This preserves timestamps, statuses, notes, and schedule membership. No historical weekday windows are inserted. Existing overlapping approvals are preserved rather than silently rewritten.

Generated SQL was inspected at `.tmp/viewing-migration.sql`. EF reports no pending model changes. Apply the migration through the normal deployment process before using these APIs. Configure property schedules explicitly before expecting tenant slots.

## 3. Weekday and timezone contract

| Contract value | Weekday |
|---|---|
| 0 | Sunday |
| 1 | Monday |
| 2 | Tuesday |
| 3 | Wednesday |
| 4 | Thursday |
| 5 | Friday |
| 6 | Saturday |

C#, JSON, PostgreSQL, and React use those explicit integers. Flutter sends a calendar date and does not generate weekdays or windows; a future Dart weekday conversion must map Dart Sunday 7 to contract Sunday 0.

Windows are property-local times. The backend uses the stored IANA timezone through `TimeZoneInfo`, not a fixed offset. It returns local display labels and UTC instants. Viewing responses also include `timeZoneId`, `requestedLocalDate`, and `requestedDisplayTime`, allowing mobile and web request screens to display property-local appointments. Existing client fixtures without those optional fields retain their previous display fallback.

## 4. Slot generation

The backend verifies property existence and `IsAvailable`, loads the saved schedule, selects the property's local weekday, and generates complete intervals in duration increments. Starts are sorted. No start is generated at the window end, and incomplete remainders are discarded.

Current or earlier UTC instants are removed. Past local dates return an empty `past` state. Missing schedules return `unconfigured`; unavailable weekdays return `disabled`; a configured day with no remaining slots returns `empty`. Only approved overlaps are removed. Ambiguous/invalid DST endpoints and intervals whose UTC duration changes across a timezone transition are omitted. Out-of-range dates produce a controlled validation response.

## 5. Blocking and conflict policy

Pending requests never reserve a slot. Approved requests block overlapping intervals for the same property, using the saved request duration. Rejected, Cancelled, and Completed requests do not block.

Overlap is half-open: `existingStart < candidateEnd && existingEnd > candidateStart`. Adjacent appointments are allowed. The same-tenant/property/exact-instant duplicate rule still examines all statuses, including cancelled and rejected requests.

## 6. Concurrency solution

`ViewingPropertyLock` begins a relational transaction and issues a parameterized PostgreSQL `SELECT ... FOR UPDATE` on the property. Creation, approval, rejection, cancellation, and schedule saves use that strategy. Request state is reloaded after the lock; writers acquire property first, then request/schedule state.

Creation evaluates schedule membership and conflicts inside the transaction. Approval verifies Pending status, a future instant, and no approved overlap. A conflicting approval returns 409 and leaves the request Pending. Successful request/decision notifications remain in the same transaction as the business save. The existing cancellation notification behavior is unchanged.

The lock operates across API instances. Exact duplicates are checked after acquiring it. EF InMemory remains suitable for rule tests; real PostgreSQL tests verify lock waiting and final invariants.

## 7. Backend APIs

| API | Authorization | Result |
|---|---|---|
| GET `/api/properties/{id}/viewing-availability` | Owning landlord or admin | Property ID, IANA timezone, duration, windows |
| PUT `/api/properties/{id}/viewing-availability` | Owning landlord or admin | Atomic replacement; authoritative saved schedule |
| GET `/api/properties/{id}/viewing-slots?date=YYYY-MM-DD` | Tenant | Date, timezone, duration, state, real slots |
| POST `/api/viewings` | Tenant | Existing contract; stronger validation; always Pending |
| Existing approve/reject/cancel APIs | Existing roles/ownership | Protected transitions |

Private schedule ownership follows `PropertyAccessGuard`; other landlords receive 404 and tenants cannot read or modify private configuration. Admin access matches the existing viewing conventions. Invalid dates require exact calendar-date formatting. Schedule validation rejects invalid/duplicate weekdays, unsupported timezones, overnight windows, non-minute boundaries, and enabled windows shorter than their duration. Durations are 30, 45, 60, or 90 minutes.

## 8. Landlord web schedule UI

Edit Property contains a separate compact Viewing availability section with its own API-backed save, timezone label, duration selector, and seven weekday controls. Unconfigured schedules display disabled blank weekdays without inventing enabled hours. Enabling a day requires the landlord to enter times.

Load/save errors, retry, inline boundary validation, and unsaved state are visible. Save success is shown only after the returned property-scoped response is verified. Dirty schedule edits participate in the existing navigation warning. Other listing changes cannot be submitted while unsaved schedule edits would be lost. Property Details adds an owner-only link to the editor section; the tenant Property Details layout is unchanged.

## 9. Flutter date picker

The compact date field opens Flutter's Material `showDatePicker()`. It permits today through today +365 days using the device's calendar for picker bounds. The backend remains authoritative for elapsed slots in the property's timezone. `AvailableFrom` is not used as a minimum date. A new date clears the old slot and starts a fresh API request.

## 10. Flutter slot behavior

Before selecting a date, no time options appear. The screen shows a compact loading indicator, retryable error, truthful empty state, or backend slots in a responsive Wrap. Selected slots use dark olive and white text. A request version counter prevents older responses from replacing the current date's results. The property card uses the real Property object and existing metadata/image URL APIs, with a truthful fallback when no photo is available. No property UUID appears in the booking summary.

## 11. Submission and revalidation

Confirm Viewing is disabled without a valid available property, selected date, selected current slot, or while loading/submitting. Flutter sends the returned `requestedDateTime` string unchanged; it does not rebuild an instant from device-local date/time. Notes are optional, trimmed, and retain the 500-character input limit. The backend explicitly validates the note limit.

POST verifies current property eligibility, future time, exact current schedule-slot membership, approved overlaps, authenticated tenant identity, and the original duplicate policy. Duration is taken from the current backend schedule. On 409, Flutter preserves date/note, clears selection, reloads slots, and displays: “That time is no longer available. Please choose another slot.”

## 12. Success wording

The dedicated success state appears only after an authoritative Pending response for the selected property and instant:

> Request sent
>
> We'll let you know when the landlord responds.
> Nothing is confirmed until they approve it.

“View my requests” opens the existing My Viewings screen and retrieves fresh data. “Back to property” returns to the previous screen. No immediate confirmation or booked wording is used.

## 13. AvailableFrom behavior

`AvailableFrom` continues to represent move-in availability. It never limits viewing date selection or backend slots. Tests cover viewing requests before a future move-in date. `IsAvailable` remains the independent enquiry gate and is now enforced by backend viewing creation.

## 14. Files changed

Backend application:

- `backend/RentFlow.Api/Models/{Property,ViewingRequest,PropertyViewingAvailability}.cs`
- `backend/RentFlow.Api/DTOs/Viewings/{ViewingAvailabilityDto,ViewingResponseDto}.cs`
- `backend/RentFlow.Api/Services/{ViewingAvailabilityService,ViewingPropertyLock,ViewingService}.cs`
- `backend/RentFlow.Api/Controllers/ViewingAvailabilityController.cs`
- `backend/RentFlow.Api/Data/ApplicationDbContext.cs`
- `backend/RentFlow.Api/Data/Migrations/20261002075438_AddPropertyViewingAvailability.cs` and its designer
- `backend/RentFlow.Api/Data/Migrations/ApplicationDbContextModelSnapshot.cs`
- `backend/RentFlow.Api/Program.cs`

Backend tests:

- `backend/RentFlow.Api.Tests/Services/{ViewingAvailabilityServiceTests,ViewingServiceTests}.cs`
- `backend/RentFlow.Api.Tests/Authentication/{ViewingAvailabilityEndpointsTests,BusinessAuthorizationTests,NotificationEventsTests}.cs`
- `backend/RentFlow.Api.Tests/Data/ViewingPostgresTests.cs`

React:

- `web/rentflow-web/src/features/properties/components/ViewingAvailabilityEditor.jsx`, its test, and `viewing-availability.css`
- `web/rentflow-web/src/features/properties/services/viewingAvailabilityApi.js`
- `web/rentflow-web/src/features/properties/pages/{PropertyFormPage,PropertyDetailsPage}.jsx`
- `web/rentflow-web/src/features/viewings/components/ViewingCard.jsx`
- `web/rentflow-web/src/features/viewings/pages/MyViewingsPage.jsx`

Flutter:

- `mobile/rentflow_mobile/lib/features/properties/screens/property_details_screen.dart`
- `mobile/rentflow_mobile/lib/features/viewings/models/{viewing,viewing_slots}.dart`
- `mobile/rentflow_mobile/lib/features/viewings/services/viewing_api_service.dart`
- `mobile/rentflow_mobile/lib/features/viewings/screens/{book_viewing_screen,my_viewings_screen,landlord_viewing_requests_screen,landlord_viewing_request_details_screen}.dart`
- `mobile/rentflow_mobile/test/book_viewing_screen_test.dart`

This report is the only documentation addition. Existing unrelated agent temporary-file status entries were not changed.

## 15. Backend validation results

- `dotnet restore`: passed; dependencies up to date.
- Release build: passed, zero warnings/errors.
- Focused Viewing/BusinessAuthorization/NotificationEvents filter: **95 passed, zero failed/skipped**.
- Full backend suite with PostgreSQL enabled: **651 passed, zero failed/skipped**.
- EF pending-model check: no changes since the generated migration.
- Generated incremental migration SQL: inspected; only the described additive schema changes, transaction, and migration-history entry.

## 16. PostgreSQL results

Executed against a disposable localhost PostgreSQL 18.4 instance and a database named `rentflow_component3_test_viewing`. Tests retain the repository's `rentflow_component3_test` safety-prefix check and isolate themselves in generated schemas. The existing CI PostgreSQL connection variable discovers these tests automatically.

New focused PostgreSQL coverage: **3 passed, zero failed/skipped**:

1. Legacy duration migration preserves time/status and creates no schedule windows.
2. Competing overlapping approvals wait on a held property lock; one succeeds, one remains Pending, and one approval notification is persisted.
3. Concurrent identical tenant submissions persist one request; another tenant can still submit Pending at that time.

The full backend run includes **7 PostgreSQL tests**, all passing. It also verifies compatibility with existing database migrations. The temporary PostgreSQL server was stopped after validation; test reports and generated SQL remain in ignored local artifact directories.

## 17. React results

- Focused property form/details/editor tests: **44 passed**.
- New editor tests: **7 passed**, covering empty schedules, saved windows, validation, duration, authoritative save, failure preservation, disabled-day clearing, and response isolation.
- Full suite: **460 passed across 48 files**, zero failed.
- Changed-file ESLint: passed.
- Production build: passed. Vite retains its bundle-size advisory.

One initial full run timed out in an existing wizard test under higher worker contention. The entire suite passed with `--maxWorkers=2`; no test expectation or timeout was weakened.

## 18. Flutter results

- `flutter pub get`: passed.
- `flutter analyze`: passed with no issues.
- Focused Book Viewing tests: **14 passed**, including real image metadata/URL loading, enforced note length, date selection, response races, loading/error/empty states, exact UTC submission, duplicate-tap prevention, stale conflict recovery, request-list navigation, and 320px/2x-text coverage.
- Full Flutter suite: **282 passed**, zero failed.
- Debug APK build: passed at `mobile/rentflow_mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: passed for the changed application, test, and documentation paths.

## 19. Remaining limitations

- This version supports one window/day, no overnight windows, and no blackout dates.
- Conflict capacity is property-scoped; simultaneous appointments at different properties owned by the same landlord are allowed by the requested policy.
- Existing legacy approvals are not automatically moved or cancelled. Their duration is the explicitly approved 60-minute backfill.
- Schedule/timezone changes do not move saved request instants or change their duration. Existing Pending requests may still be approved if future and nonconflicting, even when no longer a current schedule slot; approval deliberately does not invent legacy schedule membership.
- The landlord timezone is persisted and validated by API; the web editor displays it read-only. The initial deployment uses `Asia/Colombo`.
- Flutter picker bounds use the device's current calendar date; property-zone slots and elapsed-time decisions remain server-authoritative.
- The migration is ready for normal deployment but was not applied to an application database. Existing properties require explicit landlord configuration to return slots.
