# Flutter viewing UX and typography polish

Implemented on the existing `feature/mobile-ui-redesign` branch. No branch operation, commit, push, or PR. No React files changed. Backend changes are limited to required viewing notes and richer slot metadata; existing authorization, property scheduling, approval locking, and `AvailableFrom` behavior remain intact.

This follow-up supersedes the earlier report's optional-note UI and bookable-only Flutter display descriptions. The underlying property availability model and migration are unchanged.

## 1. Book Viewing header and layout

The app bar contains only an accessible back button. The body has one **Request a viewing** title and **Select your preferred date and time** subtitle. The real property image, wrapped title, city, and comma-formatted rent remain in a compact card. The existing branded image fallback is retained. No UUID appears in the booking form or review card.

The date control has less vertical padding; section gaps stay around 20–24 logical pixels. The form scrolls naturally, including at large text sizes.

## 2. Date picker

The compact date field continues to open Material `showDatePicker()`. Past device-calendar dates are disabled; the horizon stays today +365 days. `AvailableFrom` never restricts selection. Changing dates clears the old slot and requests fresh server availability. Older network responses cannot replace the current date's result.

## 3. Final slot response

To preserve older clients, GET `viewing-slots?date=YYYY-MM-DD` still returns **bookable-only** `slots`. The redesigned Flutter client opts into configured blocked times using `&includeUnavailable=true`. Both variants add `isAvailable` and nullable `unavailableReason` fields. No appointment IDs or tenant information are exposed.

Example for the opt-in response:

```json
{
  "date": "2026-10-30",
  "timeZoneId": "Asia/Colombo",
  "slotDurationMinutes": 60,
  "state": "available",
  "slots": [
    {
      "localTime": "09:00",
      "displayTime": "9:00 AM",
      "requestedDateTime": "2026-10-30T03:30:00Z",
      "isAvailable": true,
      "unavailableReason": null
    },
    {
      "localTime": "10:00",
      "displayTime": "10:00 AM",
      "requestedDateTime": "2026-10-30T04:30:00Z",
      "isAvailable": false,
      "unavailableReason": "ApprovedViewing"
    }
  ]
}
```

This is an illustrative contract, not an inserted schedule. Flutter stores the returned duration and forwards the exact server timestamp. Missing availability flags on an older server's bookable-only response default to available. Invalid flag/reason types are rejected by the parser.

## 4. Blocked-slot presentation

**Available times** uses responsive chips. Selected times have dark olive fill and white text. Approved overlaps are disabled, struck through, and labelled **Booked**; their `onSelected` handler is null. Native chip semantics retain the disabled state and readable time/reason. Unknown unavailable reasons use **Unavailable**.

Elapsed and invalid/DST-ambiguous slots continue to be omitted. An all-blocked configured day displays the no-available-times message together with its disabled configured chips.

Loading stays compact. Unconfigured schedules display only **Viewing times have not been configured for this property yet.** Other empty days display **No viewing times are available on this date.** Failures display **Viewing times could not be loaded.** and **Retry**.

## 5. Blocking policy

Pending requests do not reserve or block times. Approved intervals block overlapping slots using their snapshotted duration. Rejected, Cancelled, and Completed requests do not block. Adjacent intervals remain allowed. No approval state transition or locking rule changed.

## 6. Required note

Creation requires a trimmed, nonblank landlord note, with a maximum of 500 characters under the existing backend string-length convention. Null, empty, and whitespace-only notes return controlled HTTP 400 without saving a request or notification. One-character and 500-character notes are accepted; 501 characters are rejected. Surrounding whitespace is removed before length validation and persistence. Authenticated tenant identity still comes from the JWT.

Flutter shows **A note for the landlord \***, **Required**, and **Add anything helpful about your visit.** The field has 3–5 lines and its 500-character counter/limit. Its counter and validation match the backend's trimmed UTF-16 string-length convention, including emoji notes; the existing input limiter remains. Whitespace or overlong input shows an inline error. Send remains disabled until a valid note and current available slot exist. Historical rows and their nullable messages are not rewritten.

## 7. Request summary

The light review card contains **Request summary**, real property title/city, separate Date/Time/Duration labels, server duration in minutes, and the trimmed note. Values wrap naturally. Before a note is entered, the draft review prompts **Add a note above**; there is no **No message added** state on a valid form.

## 8. Primary CTA

The full-width dark olive button reads **Send viewing request**, uses the shared 15px/700 button style, and has a 54px minimum height. During submission it reads **Sending request...**. Both the handler and disabled UI prevent duplicate submission and blocked-slot selection.

## 9. Success and stale requests

Success still requires an authoritative Pending response for the selected property and exact instant. It displays:

> Request sent
>
> We'll let you know when the landlord responds.
> Nothing is confirmed until they approve it.

**View my requests** and **Back to property** retain their existing navigation. A 409 preserves the selected date and required note, clears the stale slot, refreshes availability, and displays **That time is no longer available. Please choose another slot.**

## 10. Floating-control audit

`SharedAppShell`, `BookViewingScreen`, the application root, and the Android activity contain no floating menu button or menu overlay. Property Details already pushes booking through the root navigator, so booking owns its Scaffold and chrome. No global shell controls were removed.

A new regression test follows the actual shell → discovery → property details → booking path. It verifies one booking app bar/back button, no visible shell navigation, no floating button/menu icon, and restoration of the original discovery navigation after returning.

The screenshot's control resembles Flutter's developer widget-selection overlay. The installed SDK creates that overlay outside the feature tree, including a circular selection-mode control. Its exact live source could not be verified: the debug attach attempt did not obtain a connection, and the emulator was subsequently on its launcher. The temporary attach helper was stopped. **No claim is made that an unidentified external/developer overlay was removed through application code.** If it remains in a debug run, exit Select Widget mode in Flutter Inspector; the production app's navigation regression is covered separately.

## 11. Central typography

`AppTypography` lives in the existing `app_theme.dart` and supplies the single `ThemeData.textTheme` scale. Existing theme consumers inherit it; local color/weight variants use these shared styles or semantic size constants. No font dependency or font-family change was introduced.

All TextTheme display/headline sizes are explicitly defined, so an unset Material headline cannot unexpectedly fall back to 28–32px. FilledButton, OutlinedButton, TextButton, input label/hint/error/counter, chip, tab, app-bar, and navigation typography use the same scale. The authentication theme inherits shared input typography rather than replacing it with Material defaults.

## 12. Semantic scale

| Role | Logical px | Weight | Typical height |
|---|---:|---:|---:|
| Rare display/landing hero | 28 | 700 | 1.15 |
| Page title | 24 | 700 | 1.15 |
| Section title/app-bar title | 18 | 700 | 1.2 |
| Card title | 16 | 600 | 1.3 |
| Body large/input/button | 15 | 400 / 700 button | 1.4 / 1.3 |
| Body/hint | 14 | 400 | 1.4 |
| Body small/subtitle | 13 | 400 | 1.35 |
| Label/chip/floating field label | 12 | 600 | 1.3 |
| Caption/counter/navigation | 11 | 500 | 1.35 |
| Eyebrow | 11 | 700 | 1.3; spacing 1 |

## 13. Local styles removed and area audit

The public landing hero changes from 48 to 28; its marketing section titles from 34 to 24. Login/registration titles change from 28 to the shared 24px page style. Discovery, Property Details, match preferences, dashboard, and profile title/metadata variants use shared typography. The dashboard's local size-based style helper now takes shared TextStyle bases. Property rent emphasis uses 18px rather than a competing page-sized amount.

Local numeric `fontSize` literals outside the theme were removed. The brand wordmark retains its intentional size parameter for logo presentation; it now uses Flexible text and wraps rather than overflowing. Auth hero text no longer uses FittedBox to shrink accessibility text.

The following existing areas already consume the shared TextTheme and were audited without business/layout redesign: notifications; My Viewings and landlord viewing review; rental application queues, forms, details and validation; document screens; maintenance lists/technician work and estimates; landlord home; and generic technician/admin/profile/navigation screens. Their hierarchy updates through the central theme. Theme button minimum tap targets remain readable.

## 14. Accessibility and layout results

Text scaling remains enabled with no global clamp. New regressions exercise 320px layouts at **1×, 1.3×, and 2×** for discovery, property details, application form, maintenance form, tenant dashboard, profile, login, and landlord/technician/admin navigation. They check initial and scrolled content.

Complete Book Viewing flows, including the calendar dialog, slot selection, note, summary, and success, pass at all three scales. Existing responsive tests also cover 720×1560 at 2 device pixels/logical pixel and 1080×2340 at 3, plus narrow Property Details/discovery/profile/dashboard cases. No overflow exceptions remain in these checks.

The tests exposed maintenance dropdown overflow; expanded, variable-height items now wrap. The auth brand row is flexible and its containing chrome grows naturally. These are small layout corrections, with unchanged values, actions, role guards, and APIs.

## 15. Files changed

Backend:

- `backend/RentFlow.Api/DTOs/Viewings/ViewingAvailabilityDto.cs`
- `backend/RentFlow.Api/Controllers/ViewingAvailabilityController.cs`
- `backend/RentFlow.Api/Services/ViewingAvailabilityService.cs`
- `backend/RentFlow.Api/Services/ViewingService.cs`
- `backend/RentFlow.Api.Tests/Authentication/ViewingAvailabilityEndpointsTests.cs`
- `backend/RentFlow.Api.Tests/Services/ViewingAvailabilityServiceTests.cs`
- `backend/RentFlow.Api.Tests/Services/ViewingServiceTests.cs`
- `backend/RentFlow.Api.Tests/Data/ViewingPostgresTests.cs`

Flutter (paths relative to `mobile/rentflow_mobile`):

- `lib/shared/theme/app_theme.dart`
- `lib/shared/widgets/{shared_widgets,rentflow_brand}.dart`
- `lib/shared/home/tenant_home.dart`
- `lib/shared/profile/shared_profile_content.dart`
- `lib/features/auth/screens/{login_screen,register_screen}.dart`
- `lib/features/auth/widgets/auth_shell.dart`
- `lib/features/landing/screens/public_landing_screen.dart`
- `lib/features/application_documents/screens/application_documents_screen.dart`
- `lib/features/maintenance/screens/create_maintenance_request_screen.dart`
- `lib/features/properties/screens/{match_preferences_screen,property_details_screen,property_list_screen}.dart`
- `lib/features/properties/widgets/{discovery_filter_panel,property_card}.dart`
- `lib/features/viewings/models/viewing_slots.dart`
- `lib/features/viewings/services/viewing_api_service.dart`
- `lib/features/viewings/screens/book_viewing_screen.dart`
- `test/book_viewing_screen_test.dart`
- `test/typography_layout_test.dart` (new)

Documentation: this report. Audit scripts/logs are ignored local artifacts under `.tmp`; unrelated existing agent temporary-file status entries were untouched.

## 16. Backend validation

- Restore: passed, dependencies up to date.
- Release build: passed, **0 warnings/errors**.
- Focused Viewing/BusinessAuthorization/NotificationEvents: **101 passed, 0 failed/skipped**.
- Full backend suite: **657 passed, 0 failed/skipped**.
- EF pending-model check: **no changes since the last migration**. No schema/model changes or new migration are needed.

The six added HTTP note cases cover null/blank/whitespace, 1/500/501 characters, trimming, persistence, controlled errors, notifications, and JWT identity. Existing tests still exercise slot submission, authorization, interval blocking, and approval races.

## 17. PostgreSQL validation

All **7 real PostgreSQL tests** passed in the full backend run. The three viewing PostgreSQL tests are included in the focused run: legacy migration preservation, competing overlapping approvals under a held property row lock, and concurrent duplicate submissions.

The competing-approval test now also verifies the opt-in blocked-slot response against the persisted winner, bookable-only compatibility, correct reason, and rejection of a returned blocked instant. Existing race protections remain intact.

Tests used the disposable `rentflow_component3_test_viewing` database on local PostgreSQL 18.4, preserving the existing safety-prefix checks and isolated schemas. No application database was modified.

## 18. Flutter analysis and formatting

`flutter pub get` passed. Changed Dart files were formatted. `flutter analyze` passed with **no issues**. `git diff --check` passed for the changed backend/mobile/documentation paths. No React validation was necessary because React files are unchanged.

## 19. Flutter tests

- Focused Book Viewing: **20 passed**.
- New typography/navigation regression file: **4 passed**.
- Combined focused run: **24 passed, 0 failed**.
- Full Flutter suite: **292 passed, 0 failed**.

The booking tests include exact UTC submission, disabled blocked times and selected styling, required/whitespace/limited note, counter/summary, unconfigured/loading/error/empty states, response races, double submit, 409 preservation, success wording, and request-list navigation.

## 20. APK

`flutter build apk --debug` passed. Artifact: `mobile/rentflow_mobile/build/app/outputs/flutter-apk/app-debug.apk`. The build retains the existing Gradle/JDK native-access advisory. No emulator installation or release deployment was performed.

## 21. Remaining limitations

- The screenshot's external/development floating control could not be live-identified; the product booking route itself has no floating control. See section 10.
- A full manual device walkthrough and screen-reader walkthrough were not completed. Automated render, interaction, and large-text regressions passed.
- The note length convention is UTF-16 units, consistently validated and counted in Flutter and the backend; one emoji can consume two units. No global text scaling restriction was added.
- The React viewing form was deliberately left unchanged; clients that previously sent an empty note now receive the required-note 400.
- Existing version-one scheduling limits remain: one window per weekday, no overnight/blackout model, property-scoped capacity, and device-calendar picker bounds with server-authoritative timezone slots.

Availability and `AvailableFrom` rules, historic viewing data, authenticated identity, and Pending/Approved semantics are preserved.
