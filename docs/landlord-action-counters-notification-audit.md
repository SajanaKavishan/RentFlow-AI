# Landlord action counters and notification integration

Work performed on the current branch. No commit, push, PR, or branch operations.

## Audited semantics

| Module | Required action counted | Exclusions |
| --- | --- | --- |
| Maintenance | Submitted: triage; Triaged: assign technician; Assigned: request an estimate; AwaitingLandlordApproval: review estimate | EstimatePending and EstimateSubmitted wait on the technician; Approved and InProgress wait on work; Rejected, Completed, Cancelled are excluded |
| Maintenance AI | Latest coordination workflow is AwaitingHumanReview, requires human approval, approval Pending; counts the request once, including when another maintenance action also applies | Superseded, reviewed, failed, running and pending workflows; terminal maintenance requests |
| Lease | Accepted offer without any lease: create lease; Pending lease: activate | Offers waiting on tenant, rejected/withdrawn/expired offers; Active/Terminated/Completed leases; offers already represented by a lease |
| Payments | Manual-provider Pending payment: existing Complete/Fail review actions | Stripe Pending is automatic; Completed and Failed have no landlord settlement action; future rent schedule rows are not counted |
| Pricing | No mandatory landlord approval/review state exists | No standalone pricing counter or fabricated pricing notification |

Assigned is intentionally counted: the actual landlord Maintenance page exposes
Prepare/request estimate, and the technician cannot submit an estimate until
the landlord transitions Assigned to EstimatePending. This differs from a
generic workflow that considers every Assigned request technician-only.

Overdue schedules are refreshed by RentScheduleService during reads, and failed
payment records exist. Neither exposes a landlord recovery/approval transition.
No overdue/failed action badge or invented recovery notification was added.
The existing schedule/outstanding-payment reporting remains available.

## Existing architecture preserved

- Viewing Requests: Pending; Rental Applications: Submitted/UnderReview. Existing
  contexts, scope behavior, acknowledgement/dismissal behavior and notification
  delivery preferences are unchanged.
- Existing viewing/application notifications persist to Notifications and use
  lifecycle transition guards. Application resubmissions remain distinct events.
- Technician assignment notifications retain their existing recipient and
  deduplication behavior. Security and technician-activation notifications remain.
- Bell count queries unread persisted notifications for the authenticated
  recipient; it is independent of current actionable-resource counts.

## Counter architecture

GET `/api/landlord/actions/summary` derives the landlord from the current JWT.
It returns maintenanceCount, maintenanceByProperty, leaseCount and paymentCount.
Owned-property subqueries constrain every module. Maintenance is grouped in the
database; latest AI review is a correlated database expression. No per-property
counter HTTP requests are made. The endpoint uses four aggregate/grouped queries.

AppShell makes one summary request and shares it through LandlordActionsContext.
The global Maintenance badge is the sum of property counts. The Maintenance
selector uses the same summary for option labels and compact property chips;
zero badges are hidden. The Pricing / Lease badge contains lease work only.
Payments includes manual review work only. Invalid/failed summaries hide badges
instead of displaying invented values. Identity/route changes abort old requests.

Refresh occurs on navigation, landlord window focus and relevant successful
maintenance/coordination/lease/payment mutations. Existing bell refresh behavior
is preserved; local notification-producing transitions and window focus refresh
the unread count. There is no new WebSocket/SSE or background overdue scanner.

## New persisted notification events

| Event | Source | Destination |
| --- | --- | --- |
| maintenance_request.submitted | Request creation | Owning property's maintenance request |
| maintenance_request.triaged | Triage completion | Owning property's maintenance request |
| maintenance_request.estimate_preparation | Technician assignment | Owning property's maintenance request |
| maintenance_request.estimate_review | Estimate sent for landlord approval | Owning property's maintenance request |
| maintenance_request.coordination_review | AI result reaches human review | Owning property's maintenance request |
| rental_offer.accepted | Tenant accepts offer | Lease creation with accepted offer preselected |
| lease.activation_required | Pending lease created | Specific lease details |
| payment.manual_review | Tenant creates manual payment | Specific payment details |

Recipient is resolved server-side from the property's current landlord; no
caller-supplied recipient/landlord ID is trusted. Notifications are persisted in
the same SaveChanges as the corresponding authoritative transition. New
operational events have their own always-delivered category because existing
preferences cover only viewing/application events; no preferences are fabricated.

New notifications have deterministic primary keys derived from recipient, event
type and source-event ID. Existing tracked/stored rows are checked before queueing;
the database primary key also prevents concurrent duplicate rows. Revised
estimate and separate AI-run IDs permit distinct legitimate review events.
Text contains no generated raw UUIDs. No historical events are backfilled.

Navigation validates the supported event/resource combination and role, then
loads the resource through its existing authorized endpoint before routing.
Cross-landlord resources remain inaccessible. Read notifications remain events
even after their corresponding action has been completed.

## Files changed for this request

Backend API paths under `backend/RentFlow.Api`:
- Controllers/LandlordActionsController.cs (new)
- DTOs/Payments/PaymentResponseDto.cs (provider for truthful manual-action UI)
- Services/MaintenanceRequestService.cs
- Services/MaintenanceCoordinationOrchestrator.cs
- Services/RentalOfferService.cs
- Services/LeaseAgreementService.cs
- Services/PaymentService.cs
- Services/NotificationDeliveryPolicy.cs
- Services/NotificationEventTypes.cs

Backend tests:
- backend/RentFlow.Api.Tests/Authentication/LandlordActionCountersTests.cs (new)
- backend/RentFlow.Api.Tests/Services/MaintenanceRequestServiceTests.cs

Web paths under `web/rentflow-web/src`:
- shared/layout/AppShell.jsx
- shared/layout/LandlordActionsContext.js (new)
- shared/layout/useLandlordActionSummary.js (new)
- shared/layout/LandlordActions.test.jsx (new)
- shared/layout/landlordActionSummary.test.js (new)
- features/maintenance/pages/LandlordMaintenancePage.jsx
- features/maintenance/maintenance.css
- features/leaseAgreements/pages/LeaseAgreementsPage.jsx and .test.jsx
- features/payments/pages/PaymentsPage.jsx and .test.jsx
- features/notifications/notificationNavigation.js
- features/notifications/notificationTypes.js
- features/notifications/landlordNotificationNavigation.test.js (new)
- shared/pages/LandlordDashboard.test.jsx (isolates new shell-summary request)
- shared/property/PropertyWorkflowIntegration.test.jsx (new authorized summary request)
- shared/pages/TechnicianAssignedWorkPage.test.jsx (permits landlord shell summary, still blocks technician APIs)

This report is `docs/landlord-action-counters-notification-audit.md`.

## Validation and limitations

Backend focused suites: 608 passed, including real transition notification
creation, deduplication, unread counts, ownership, precise action states, latest
AI review, waiting/final exclusions and existing notification/service regression
tests. Backend validation used a temporary output folder because the running API
locks normal build outputs. An existing broken TechnicianWorkspaceDisplayTests.cs
was temporarily excluded from test compilation; repository test files were not
deleted or changed for that exclusion.

Full web run: 709 passed, 16 failed (725 total). Remaining failures are in
shared/shell.test.jsx, maintenanceCoordinationUi.test.jsx,
NotificationNavigation.test.jsx, StaffDashboards.test.jsx,
TechnicianAssignedWorkPage.test.jsx, TechnicianWorkspace.test.jsx and
ApplicationPropertySelector.test.jsx. They involve other navigation/heading,
technician workspace, old integration-placeholder and selector expectations.
The full suite is not green. They were not broadened into unrelated feature fixes.

Final focused web: 86 passed across eight suites. Full web lint passed. Frontend
production build passed, with the existing bundle-size advisory. Backend build
passed with zero warnings/errors. Tracked and new-file whitespace/diff checks
passed. The API must be restarted to load the new summary route and event hooks.
