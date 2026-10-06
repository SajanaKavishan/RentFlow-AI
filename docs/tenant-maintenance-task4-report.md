# Maintenance Task 4 implementation report

Implemented on `feature/full-app-polish`. No branch operations, commit, push or PR were performed by this task.

## 1. Final Tenant card hierarchy

The existing summary retains the category icon, real title, category/full reference, status/priority chips, created date and expand/collapse semantics. Expanded content is now description text, a compact clock/access row with actual access notes, assigned-technician identity/contact, connected Updates, and compact Attachments. No overview property subtitle or unit text is fabricated.

## 2. Work-contact architecture

`ApplicationUser.MaintenanceContactPhone` is nullable and limited to 32 characters. `MaintenanceContactEnabled` defaults to false. These fields are independent of account `PhoneNumber` and Landlord public contact. Existing accounts receive disabled contact and a null work phone; the migration never copies private phone data.

The existing authenticated `PUT /api/auth/profile` accepts optional work-contact settings only for a MaintenanceTechnician. Omitted settings preserve the stored values. The server reuses `PhoneNumberValidation.UsablePhoneNumber`: trimmed input, supported punctuation, 7–15 digits and at most 32 characters. Enabling requires a usable number.

## 3. Tenant disclosure and privacy

Owning-Tenant `GET /api/maintenance-requests/{id}` returns the actual assigned name and `assignedTechnicianContactPhone` only for a matching MaintenanceTechnician account that is active, opted in and has a usable saved work number. Other Tenants receive 404. Other request-reader roles receive no contact projection. Responses use `private, no-store`. Summary and mutation projections do not disclose the work number.

The projection selects the dedicated work contact, never account `PhoneNumber` or email. The explicit Profile-phone choice can publish a copy of the selected number only on Save; later private-phone edits do not mutate that saved work contact. The Flutter summary parser ignores contact fields.

Staff history notes lack a Tenant-safe visibility marker: Tenant history responses redact Notes and the Tenant timeline never renders them. Persisted history and staff-reader notes remain unchanged.

## 4. Technician Profile

Flutter Profile has a Technician-only Work contact row. It reuses the Landlord contact editor with a Technician mode: profile-phone/custom-number choices, publication toggle, explicit Save/Cancel, shared validation and snapshot explanation. Disabling preserves the stored number. Tenant, Landlord and Admin do not see this row or receive these self-profile fields.

## 5. Call behavior

The assigned-technician card uses initials from the real display name. A valid dedicated detail contact creates a phone icon plus Call, labelled `Call assigned technician`. `phoneDialerUri` validates and formats a `tel:` URI; `launchUrl` uses the external application mode. There is no automatic/direct call, CALL_PHONE permission, SMS, WhatsApp or private-phone fallback. Unsupported devices get a truthful error snackbar. At narrow widths or large text scale the action moves below the identity to prevent collisions.

## 6. Timeline event mapping

Only real history records produce nodes. Mapping uses FromStatus and ToStatus, including the distinct estimate-revision path:

| Persisted transition | Tenant label |
| --- | --- |
| null → Submitted | Request submitted |
| Submitted → Triaged | Request reviewed |
| Triaged → Assigned | Technician assigned |
| Assigned → EstimatePending | Estimate requested |
| EstimatePending → EstimateSubmitted | Estimate submitted |
| EstimateSubmitted → AwaitingLandlordApproval | Awaiting landlord approval |
| AwaitingLandlordApproval → Approved | Estimate approved |
| AwaitingLandlordApproval → Rejected | Estimate rejected |
| AwaitingLandlordApproval → EstimatePending | Estimate revision requested |
| Approved → InProgress | Work started |
| InProgress → Completed | Request completed |
| an actual transition to Cancelled | Request cancelled |

Unexpected legacy transitions use `Request updated`, never raw enum/arrow text. No Parts ordered or On-site visit scheduled event is synthesized.

## 7. Visual timeline

The dedicated `MaintenanceTimeline` sorts records by ChangedAt, then ID; renders small nodes and thin connected lines; uses strong event labels and readable local timestamps; and accents the last record with dark olive. Empty history omits Updates. No current-status-derived events or staff notes are rendered.

## 8. Attachments

Existing authorized server metadata, upload/open/delete/retry behavior and limits are preserved. The label and paperclip/Add action align in a compact row. Empty attachments show `No attachments yet.`

## 9–10. Technician parity

Task 3's Flutter queue/detail presentation and web Technician reference fix remain present and tested. Both use full friendly references; raw request, Tenant and property IDs are not display metadata. Work/status actions and internal GUID routes are unchanged. No additional web implementation change was necessary in Task 4.

## 11. Migration

Added `20261005110150_AddTechnicianMaintenanceWorkContact`, its Designer and the model snapshot. It adds exactly two Users columns: nullable work phone and enabled/default-false. No shipped migration was edited and no private-phone backfill exists. EF reports no pending model changes. The new migration was not applied to a deployed database during this task.

## 12. Changed files

31 implementation/test/migration files, plus this report:

- `backend/RentFlow.Api/Models/ApplicationUser.cs`
- `backend/RentFlow.Api/Data/ApplicationDbContext.cs`
- `backend/RentFlow.Api/Data/Migrations/20261005110150_AddTechnicianMaintenanceWorkContact.cs`
- `backend/RentFlow.Api/Data/Migrations/20261005110150_AddTechnicianMaintenanceWorkContact.Designer.cs`
- `backend/RentFlow.Api/Data/Migrations/ApplicationDbContextModelSnapshot.cs`
- `backend/RentFlow.Api/DTOs/Auth/UpdateProfileRequestDto.cs`
- `backend/RentFlow.Api/DTOs/Auth/UserProfileDto.cs`
- `backend/RentFlow.Api/DTOs/Maintenance/MaintenanceRequestResponseDto.cs`
- `backend/RentFlow.Api/Services/AuthService.cs`
- `backend/RentFlow.Api/Services/MaintenanceRequestService.cs`
- `backend/RentFlow.Api/Controllers/MaintenanceRequestsController.cs`
- `backend/RentFlow.Api.Tests/Authentication/TechnicianMaintenanceContactTests.cs`
- `backend/RentFlow.Api.Tests/Controllers/MaintenanceRequestsAuthorizationTests.cs`
- `backend/RentFlow.Api.Tests/Data/TenantMaintenancePostgresTests.cs`
- `mobile/rentflow_mobile/lib/core/validation/phone_number.dart`
- `mobile/rentflow_mobile/lib/features/auth/controllers/auth_controller.dart`
- `mobile/rentflow_mobile/lib/features/auth/models/current_user.dart`
- `mobile/rentflow_mobile/lib/features/auth/services/auth_service.dart`
- `mobile/rentflow_mobile/lib/features/maintenance/models/maintenance_request.dart`
- `mobile/rentflow_mobile/lib/features/maintenance/screens/my_maintenance_requests_screen.dart`
- `mobile/rentflow_mobile/lib/features/maintenance/widgets/assigned_technician_card.dart`
- `mobile/rentflow_mobile/lib/features/maintenance/widgets/maintenance_timeline.dart`
- `mobile/rentflow_mobile/lib/features/properties/widgets/landlord_contact_card.dart`
- `mobile/rentflow_mobile/lib/shared/profile/public_contact_editor.dart`
- `mobile/rentflow_mobile/lib/shared/profile/shared_profile_content.dart`
- `mobile/rentflow_mobile/test/maintenance_card_polish_test.dart`
- `mobile/rentflow_mobile/test/maintenance_journey_test.dart`
- `mobile/rentflow_mobile/test/technician_work_contact_test.dart`
- `mobile/rentflow_mobile/test/maintenance_request_model_test.dart`
- `mobile/rentflow_mobile/test/maintenance_screen_test.dart`
- `mobile/rentflow_mobile/test/tenant_maintenance_redesign_test.dart`
- `docs/tenant-maintenance-task4-report.md`

The old reference-backfill PostgreSQL test now selects Task 2's actual predecessor by migration ID instead of assuming the second-last migration. This keeps its original backfill coverage meaningful after adding the new migration.

## 13–16. Validation

| Check | Result |
| --- | --- |
| Focused backend contact/maintenance/authorization/Landlord contact | 182 passed, 4 PostgreSQL tests skipped |
| Full backend suite | 967 passed, 16 PostgreSQL tests skipped |
| EF pending-model check | No pending changes |
| Focused Flutter journey/profile/maintenance/Landlord contact | 144 passed |
| Full Flutter suite, final card alignment | 1,273 passed |
| Flutter analysis | No issues |
| Debug APK, final card alignment | Built successfully |
| Focused web Technician/maintenance | 18 passed |
| Full web suite | 561 passed with 2 workers and 15-second test timeout |
| Web lint/build | Passed |
| git diff --check | Passed |

The first full web run encountered two property-wizard timing failures under parallel validation; no property code was changed. The full rerun with reduced concurrency passed. The card was rendered and visually reviewed using native-equivalent fonts; the preview uses test fixtures with an opted-in example contact.

Responsiveness checks cover 320px, 720×1560, 1080×2340, 200% text, long names/references/descriptions/labels and Call/name separation. Tests also verify dialer URI/semantics, no CALL_PHONE permission, no private fallback, conditional Call, transition/revision labels, chronology, connectors and omission of fabricated events/internal notes.

## 17. Remaining limitations and rollout

- Apply the new migration before using the new contact fields against an existing database.
- PostgreSQL migration/concurrency tests are present but skipped because no disposable test connection is configured.
- Existing technicians must explicitly enable a valid work contact; until then identity renders without Call.
- Requests still lack property title metadata; no property/unit display is invented.
- Dialer integration is verified by a native-channel test, not a real-device placed call.
- Unknown legacy transitions retain the neutral `Request updated` label.

Eligibility, zero/one/multiple-property behavior, JWT ownership, creation, assignment, estimates/status transitions, attachment authorization, required access and reference generation were preserved.
