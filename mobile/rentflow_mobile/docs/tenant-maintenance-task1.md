# Tenant Maintenance UI — Task 1 report

Implemented on `feature/mobile-ui-redesign`. No branch changes, commits, pushes,
or PRs. Backend contracts, maintenance enums, authorization, assignment, status
transitions, and other role screens/navigation were not changed.

## 1. Existing architecture

- `SharedAppShell` opens `MyMaintenanceRequestsScreen` for the existing tenant
  Maintenance destination and retains its tool icon and position.
- State resides in the maintenance screens (`StatefulWidget`, `FutureBuilder`);
  there is no separate tenant maintenance controller.
- `AuthScope` supplies the current tenant. `MaintenanceApiService` uses the
  existing authenticated `ApiClient` for listing, detail, creation, associated
  property lookup, history, and attachment operations.
- Models: `MaintenanceRequest`, `MaintenanceStatusHistory`,
  `MaintenanceAttachment`. The tenant request exposes a technician ID but no
  technician name or public phone. Technician choices belong to the existing
  assignment workflow and were not fetched for tenant presentation.
- Associated-property selection already exists. The backend
  `GET /api/properties/tenant/mine` checks an active lease within its date range,
  linked to an accepted rental offer and approved application. This behavior
  was preserved; no equivalent rule was invented in Flutter.
- Existing maintenance model/service/screen and shared shell tests were retained.

## 2. UI changes

The supplied screenshots guide composition. Colors and typography come from
the shared `AppPalette` / `AppTypography`: cream background, white cards, dark
olive actions, pale olive selections, warm amber attention, green completion,
neutral cancelled/rejected states, and restrained emergency/error red.

Reusable category icons, badges, surfaces, enum labels, and presentation filter
groups reside in `tenant_maintenance_ui.dart`. No new domain enum was introduced.

## 3. Final overview layout

The 24px Maintenance heading and compact 42px New Request action share one row
at normal text sizes, including at 320px. Enlarged text uses an intentional
stacked fallback. Three 80px summary cards, small horizontally scrollable filter
pills, and a subtle content divider establish the Figma structure without its
teal palette. Counts derive from the fetched request list. Pull-to-refresh,
loading, compact empty, filtered-empty, and error/retry states are real. The
existing associated-property dialog remains the entry to creation and now uses
the RentFlow surface, spacing, type, border, and action treatment.

## 4. Filters and status mapping

| Presentation filter | Existing statuses |
| --- | --- |
| All | Every status, including rejected and cancelled |
| Open | submitted, triaged, assigned, estimatePending, estimateSubmitted, awaitingLandlordApproval, approved |
| In progress | inProgress |
| Resolved | completed |

Cards keep the exact enum status label, including Completed. Resolved is a
presentation grouping, not a renamed backend status. Closed unsuccessful
requests are not counted as resolved. Filtering is local and makes no API or
workflow changes.

## 5. Expanded cards

Collapsed cards show the real title, category, complete request ID, status,
priority, and created date. Tapping toggles inline details and announces the
expanded/collapsed state to accessibility services.

Expansion loads the existing detail, history, and attachment endpoints. It
renders DESCRIPTION and, only when real history exists, UPDATES with actual
status transitions, timestamps, and notes. No fictional events are derived
from the current status and empty update sections are omitted.

Existing attachment upload/open/delete operations remain, including confirmation
before deletion, the same tenant ID, image extension checks, and download URL
flow. Detail, history, and attachment errors have retry actions. No private
technician phone or fabricated identity is shown.

## 6. Supported New Request fields

- Property ID comes from the existing associated-property selection.
- Categories: Plumbing, Electrical, Appliance, Structural, Security, Pest, Other.
- Priorities: Emergency, High, Normal, Low; the real enum values are submitted.
- Title and multiline description retain required, trimmed-value validation.
- Description retains the existing Flutter 2,000-character maximum.
- Optional tenant access notes retain the existing 1,000-character maximum.

The form uses wrapping category icon cards and radio-style priority rows.
It scrolls with the keyboard, disables editing/submission while a request is in
flight, and preserves the draft and selections after an API failure. The submit
action remains enabled outside submission and performs the existing validation.

## 7. Figma fields intentionally omitted

- No HVAC category: it is absent from the existing enum.
- No mock property/unit subtitle or MR-style reference: the tenant list has
  property IDs and request IDs, not display unit labels or friendly references.
- No technician name/avatar/Call: no tenant-safe identity/contact contract.
- No preferred-access-time chips: only free-text access notes are stored.
- No pre-submit photos or five-photo limit: the existing upload requires an
  already-created request ID. Supported post-creation attachments are retained.
- No 500-character description limit or 24-hour contact promise: neither is the
  existing Flutter/product contract.

## 8. Submission success

Confirmation appears only after `createMaintenanceRequest` returns a parsed,
successful API response. The summary uses that response's title, ID, category,
priority, status, and created timestamp. It does not echo draft values as
authoritative, synthesize a time/reference, or promise an SLA.

Track request returns the created response through the existing route, refreshes
the overview, selects All, expands the matching real request, and scrolls to it.
New request clears the draft/result and restores the original category/priority
defaults in the same form. Leaving the route also refreshes the overview, so a
successful request is not lost when the tenant uses system Back.

## 9. Files changed

- `lib/features/maintenance/screens/my_maintenance_requests_screen.dart`
- `lib/features/maintenance/screens/create_maintenance_request_screen.dart`
- `lib/features/maintenance/widgets/tenant_maintenance_ui.dart` (new)
- `test/maintenance_screen_test.dart`
- `test/shared_shell_test.dart`
- `test/tenant_maintenance_redesign_test.dart` (new)
- `docs/tenant-maintenance-task1.md` (this report)

## 10. Focused tests

79 tests passed across maintenance redesign, maintenance screens, models,
services, shared shell, and tenant quick-action destinations. This includes
existing landlord/technician regressions and associated-property authorization
behavior. The updated integration test verifies Track Request opens the created
request's real description/history in the overview.

The 18 redesign tests cover loading, supplied-data counts, every status
group, empty/filter-empty/error/retry, collapsed/expanded cards, accessibility
expanded state, actual category/priority choices, validation, disabled duplicate
submission, preserved failure draft, authoritative success, compact component
dimensions, same-row header placement, the polished no-property dialog, and New
Request.

Final resolution-specific rerun: all 18 redesign tests passed at 320x800 (1x),
720x1560 (2x), and 1080x2340 (3x), at 100%/200% text, with long titles/descriptions
and simulated keyboard insets. These are automated widget layout checks;
physical-device/emulator visual inspection was not performed.

## 11. Full Flutter tests

`flutter test --reporter expanded`: **1,207 tests passed**.

## 12. Flutter analysis

`flutter analyze`: **No issues found**.

## 13. APK build

`flutter build apk --debug`: **Passed**.

Artifact: `build/app/outputs/flutter-apk/app-debug.apk`.

## 14. Diff check

`git diff --check`: exit code 0, no whitespace errors. The full workspace check
reports permission warnings for five pre-existing `agent/.pytest_tmp_asus`
artifacts. `git diff --check -- mobile` is clean. Those unrelated artifacts were
not edited.

## 15. Exact Task 2 gaps

1. Audit maintenance destination visibility and create authorization against
   the existing lease/offer/application checks in the property chooser. Do not
   assume the chooser alone specifies the complete intended entitlement rule.
2. Integrate real property/unit display context in the list/confirmation if the
   product needs it. Associated-property selection already exists.
3. Define tenant-safe technician display/contact data and privacy rules before
   showing identity, avatar, or Call.
4. Define a stored preferred-access-time contract before adding structured time
   chips. Free-text access notes already work.
5. If desired, design pre-submit photo selection around the existing
   post-creation upload contract, including upload failures/retries; there is
   no missing backend photo-upload feature in the audited flow.
6. Define an explicit SLA before promising technician response times.
7. Add a friendly request reference contract or HVAC category only if required
   by the product; Task 1 uses real IDs and existing categories.
8. Reconcile the existing Flutter description cap (2,000) with the backend cap
   (4,000), and review title-length UX against the backend's 200-character limit.
   Existing form validation was not changed in this presentation task.

Status history, category mapping, priority mapping, and post-creation photo
upload already have real integrations and are not missing Task 2 contracts.
