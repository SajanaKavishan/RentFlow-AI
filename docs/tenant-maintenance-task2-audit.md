# Tenant Maintenance Task 2 — pre-change audit

Branch checked before edits: `feature/mobile-ui-redesign`.

The backend is ASP.NET Core/.NET 8, EF Core 8.0.29 and Npgsql/PostgreSQL.
`MaintenanceRequestService` handles creation and workflow transitions;
`MaintenanceRequestsController` obtains the authenticated actor and checks
ownership/roles for reads, actions and attachments. IDs are GUIDs and remain
the route identifiers.

`MaintenanceRequest` stores required Title (200), Description (4000), numeric
Category/Priority/Status, nullable technician ID, legacy TenantAccessNotes
(1000), triage/assignment/cancellation notes, and completion/created/updated
timestamps. Create currently requires a nonblank title and description;
detail and summary DTOs return the title and GUID. No public reference or
structured access window exists. Update DTOs also require a title; their
behavior can remain compatible.

Statuses are Submitted 0, Triaged 1, Assigned 2, EstimatePending 3,
EstimateSubmitted 4, AwaitingLandlordApproval 5, Approved 6, Rejected 7,
InProgress 8, Completed 9, Cancelled 10. Priorities are Low 0, Normal 1,
High 2, Emergency 3. Categories are Plumbing 0, Electrical 1, Appliance 2,
Structural 3, Security 4, Pest 5, Other 6. These are integer database columns
without category CHECK constraints; validation uses `Enum.IsDefined`.
There is no evidence that Security exclusively means locks/doors. Existing
numeric values must remain unchanged when new categories are appended.

`GET /api/properties/tenant/mine` already checks a precise rental relationship:
same tenant/property, Active lease, inclusive UTC current-date lease term,
Accepted matching offer, Approved matching application. `LeaseAgreement`
statuses are Pending, Active, Terminated, Completed. The lookup is not based
on viewings or applications alone. `MaintenanceRequestService.CreateAsync`
does not currently enforce this relationship; the rule should be shared by
lookup and creation rather than weakened or recreated in Flutter.

Attachments use `MaintenanceAttachment` metadata (GUID, request GUID,
private storage key, filename, MIME, size, optional type, uploader and date),
private Cloudflare R2 storage, and the existing POST/GET/DELETE
`/api/maintenance-requests/{id}/attachments` routes. Download URLs expire
after ten minutes. Upload permits JPEG, PNG and WEBP, requires nonempty data,
and caps files at 10 MiB. No request-level attachment-count limit exists.
Tenant ownership is checked for upload/list/download/delete. Upload occurs
after request creation and removes orphaned storage objects on persistence
failure. The new five-photo quota must be enforced with a PostgreSQL request
row lock so concurrent uploads cannot bypass it; historical attachments stay.

Mobile uses the production overview, inline detail/history/attachments, and
injected `MaintenanceApiService`. Create currently has separate title,
description (2000), access-note fields, seven categories, four priorities,
and a raw-GUID confirmation. The separate debug entry point injects offline
dependencies and is excluded from production imports/navigation.

Profile image selection uses `file_picker`, which provides existing-file
selection but no camera capture. `image_picker` is not installed. A narrow
injectable maintenance photo picker is needed for native camera/multiple
gallery selection and debug/tests. The plugin's official configuration
requires iOS camera/photo usage descriptions and does not require broad
Android storage permission. Android activity uses `singleTop` and resize
for the keyboard.

The web tenant maintenance form also consumes the create DTO and sends Title
and TenantAccessNotes. Its enum decoder uses the same numeric values. The
new required access window needs a minimal web create-control/payload update;
new categories need enum decoding. Existing web title/note controls and
4000-character server compatibility should remain.

Planned schema scope: nullable stable access-window string for legacy rows,
unique persisted server-generated public ReferenceCode with deterministic
legacy backfill, access-value CHECK, and the two appended category values.
No historical access preference will be invented and no request data deleted.
Creation will derive a deterministic title when legacy Title is omitted.
PostgreSQL tests are opt-in through a disposable test-database connection;
local PostgreSQL binaries are available for isolated validation.
