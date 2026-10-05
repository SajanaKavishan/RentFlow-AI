# Maintenance Coordination Agent — Phase 3 report

Implemented on `feature/full-app-polish`. No branch operations, commit, push, PR, database
migration, live AI calls or live storage calls were performed. Existing private attachments
and normal maintenance actions remain independent of advisory analysis.

## 1. Photo-analysis architecture

The existing on-demand persisted `POST /api/maintenance-requests/{id}/coordination-workflows`
action now prepares optional photo evidence within its agent step. Its deterministic checks,
normal final result and human review lifecycle are preserved. The existing ephemeral analysis
action uses the same mapper/preparation service. No additional public endpoint or AI service
was introduced. Tenant creation/upload never invokes analysis.

Flow: authorized manager → existing workflow checks → private image preparation → existing
authenticated Python endpoint → one optional structured vision assessment → six text graph
nodes → validated advisory result → existing workflow storage and safe DTO.

## 2. Private R2 retrieval

`MaintenancePhotoEvidenceService` calls the existing `IFileStorageService.DownloadBytesAsync`.
The existing R2 implementation retrieves private objects internally with bounded streaming;
no signed/public URL generation is used. Supported MIME types are JPEG, PNG and WEBP. Selection
is restricted to the current request, ordered by `CreatedAt`, then ID, and capped at five.
Unsupported attachment types and other requests' attachments are excluded.

## 3. Authorization before retrieval

Both controller actions retain Landlord/Admin role checks and existing resource authorization
before entering analysis. The photo service repeats authenticated role/property ownership
checks before storage access: owning Landlord allowed, other Landlord denied, Admin allowed
under existing policy, Tenant/Technician denied. HTTP and service tests assert zero storage
and agent calls for unauthorized callers. Service authentication still runs before Python
body parsing; no user JWT is forwarded to the agent/provider.

## 4. Actual image validation

Backend preparation bounds actual bytes, identifies the decoded format rather than trusting
extensions, checks MIME agreement, validates dimensions/pixel area before full decoding, and
decodes with ImageSharp. Empty, malformed, truncated, spoofed and excessive-dimension media
are omitted safely. Decoding is limited to the first frame with bounded allocator/workers.
Python independently checks strict Base64, actual MIME, decoding and the normalized-image
size/dimension bounds using the existing Pillow dependency, with decompression warnings
treated as errors. Invalid individual photos do not invalidate usable text or other photos.

## 5. Resize and payload limits

| Limit | Value |
| --- | --- |
| Photos selected | At most 5 |
| Source private download | At most 10 MiB per image |
| Source side / pixel area | At most 8192 / 20,000,000 pixels |
| Backend simultaneous decodes | 2 per process, one decoder worker per image |
| Allocator pool / allocation limit | 32 MiB / 192 MiB |
| Analysis representation | JPEG, quality 80, at most 1280 pixels per side; no upscale |
| One encoding retry when needed | At most 960 pixels per side, JPEG quality 65 |
| Analysis bytes per image / aggregate | 512 KiB / 2 MiB |
| Internal Base64 bound | 699,052 characters per photo; 2,796,208 aggregate |

Python accepts only the backend-normalized representation (at most 1280 pixels per side)
and repeats controlled encoding/aggregate checks. Oversized remaining outputs are omitted.
Proxy limits should allow at least 3 MiB for the private service request; request bodies
must stay out of access logs.

## 6. Metadata stripping

Backend orientation is normalized before resizing/copying pixels into a fresh image. The
fresh JPEG excludes original EXIF/GPS/device/timestamps, XMP, IPTC, ICC and format metadata.
Transparency is flattened onto white. Python repeats orientation/pixel-only encoding.
Original private R2 objects are unchanged. Tests verify orientation and absent profiles.

## 7. Python media contract

The existing request adds optional `evidencePhotos: [{attachmentId, contentType, mediaBase64}]`
and a maximum of two closed `photoLimitations` codes (`PhotoUnavailable`, `PhotoUnreadable`).
Photos must correlate to unique request attachment metadata; arbitrary fields, URLs, keys
and filenames are rejected. Correlation IDs do not reach the provider or text graph.
The provider receives existing `ModelMedia` objects, with no filename/storage/location/
tenant/contact/JWT fields. The Phase 1 structured final RESULT schema and flag set are
unchanged. Safe counts are additive execution metadata, separate from the result.

## 8. Prompt and image-injection hardening

The trusted vision instruction treats images and OCR-like text as untrusted evidence,
ignores embedded instructions/QR codes/links, prohibits actions, identification, private
identity/location/contact extraction, and requires strict structured output/human review.
It prohibits hidden-cause claims, safety certification, repair guarantees, exact costs,
technician competence, legal/code compliance and emergency certainty. Irrelevant/unreadable
photos cannot supply a visual category; missing suggestions require Low/Unknown confidence.
All downstream text nodes also treat derived observations as untrusted data. Provider output
is locally validated, including exact per-photo index coverage and literal human review.
No tools for maintenance mutations are exposed to models.

## 9. Graph efficiency and total deadline

There is at most one multimodal assessment for all usable photos, immediately before the
existing graph. The graph stores bounded derived `visual_evidence` (counts, closed limitations,
up to five photo assessments, at most four 300-character observations per photo). Raw bytes,
Base64 and attachment IDs never enter graph state or subsequent model inputs. The original
six text nodes/execution-step contract remain intact: text-only uses six calls, optional
photos use at most seven total calls with only one media call.

The ASP.NET linked total deadline starts before workflow queries/persistence and includes
retrieval, preprocessing and agent work. Photo preparation uses at most min(8s, total/4).
Elapsed time is deducted before the agent call; the internal header conveys the remaining
budget with a response/persistence margin. Python wraps its entire optional phase plus graph
in min(AI_TIMEOUT_SECONDS, 30s, supplied budget). Optional preparation/vision together uses
at most min(8s, Python budget/3); the vision call uses min(6s, Python budget/4). Caller
cancellation propagates; exhausted totals fail only advisory workflow state.

## 10. Text-only fallback

Zero photos is a normal text-only run and emits no photo-unavailable/unreadable flags.
Missing/unconfigured/non-vision providers use the established provider capability/configuration
rules and text fallback, with a limitation when photos exist. Vision errors, timeouts or
invalid output also fall back to text. Mandatory text-provider failure still produces the
existing safe advisory failure. No provider/model/key is hardcoded in the new implementation.

## 11. Partial-photo failure

Usable images continue when another download/decode fails. `PhotoUnavailable` describes
retrieval, budget, payload or vision availability limits; `PhotoUnreadable` describes media
that cannot be decoded or interpreted. All-photo failure still permits text analysis.
Readable irrelevant photos count as analyzed but provide no visual classification. Photos
marked unreadable by the vision response do not count as analyzed. Detected photo/category
disagreement adds `CategoryDescriptionMismatch`; visible safety concerns add
`UrgencyNeedsHumanReview`. Stored category/priority/status/assignment are never changed.
Retrieval/decode diagnostics include only exception types; maintenance vision development
diagnostics omit provider messages, including when debug diagnostics are enabled.

## 12. UI evidence indicator

The Phase 2 card adds a small optional “Photo evidence” line, including singular/plural and
truthful partial/zero wording such as “2 of 3 photos analyzed.” Counts describe selected
photos in that completed run. Missing, malformed, legacy or zero-supplied metadata is omitted.
Counts survive latest-workflow lookup and review decisions. Loading uses “Reviewing the
request details and available evidence.” PhotoUnavailable's friendly title now supports
partial analysis. The existing recommendation/review/prefill/emergency behavior is preserved.
The AI card renders no photo URLs, raw bytes, arbitrary metadata or verified-image claims.
Headless Chrome checks at 390, 768, 1280 and 1600 pixels confirmed the partial count, no
horizontal overflow, no raw JSON, and usable normal triage. Running/failure states also
preserved normal controls. Screenshots/layout results are local ignored `.tmp` artifacts;
all API responses were intercepted fixtures, with no live backend/provider/storage calls.

## 13. Persistence privacy

`FinalResultJson` contains only the unchanged structured recommendation (plus existing
human review decision details after a decision). Safe photo counts reuse the completed
agent step's existing `ValidationSummary`, so they remain available even if its old bounded
`OutputSummary` truncates a large recommendation. The public DTO validates/project counts
from that summary. No new column/migration is needed. Workflow/step fields never receive
the media request, raw images, Base64, original filenames, R2 keys, buckets, signed/public
URLs, service credentials or user JWTs. Integration tests verify the safe reload response
and unchanged authoritative maintenance state. Derived visual observations themselves are
ephemeral; only the normal final explanation and safe counts cross persistence boundaries.

## 14. Files changed

Python:

- `agent/.env.example`, `agent/README.md`
- `agent/app/schemas/maintenance.py`, `agent/app/api/routes.py`
- `agent/app/graph/maintenance_state.py`, `agent/app/agents/maintenance_nodes.py`
- `agent/app/services/maintenance_photo_evidence.py` (new)
- `agent/app/services/model_provider.py` (safe maintenance vision diagnostics)
- `agent/tests/test_maintenance_photo_evidence.py` (new)

Backend:

- `backend/RentFlow.Api/RentFlow.Api.csproj`, `backend/RentFlow.Api/Program.cs`
- `backend/RentFlow.Api/DTOs/Maintenance/MaintenanceCoordinationAgentContracts.cs`
- `backend/RentFlow.Api/DTOs/Maintenance/MaintenanceCoordinationWorkflowResponseDto.cs`
- `backend/RentFlow.Api/Services/MaintenancePhotoEvidenceService.cs` (new)
- `backend/RentFlow.Api/Services/Interfaces/IMaintenancePhotoEvidenceService.cs` (new)
- `backend/RentFlow.Api/Services/MaintenanceCoordinationRequestMapper.cs`
- `backend/RentFlow.Api/Services/MaintenanceCoordinationAgentClient.cs`
- `backend/RentFlow.Api/Services/MaintenanceCoordinationResultValidator.cs`
- `backend/RentFlow.Api/Services/MaintenanceCoordinationOrchestrator.cs`
- `backend/RentFlow.Api/Services/MaintenanceCoordinationService.cs`
- `backend/RentFlow.Api/README-MaintenanceCoordination.md` (new)
- `backend/RentFlow.Api.Tests/Authentication/AuthApiFactory.cs`
- `backend/RentFlow.Api.Tests/Controllers/MaintenanceRequestsAuthorizationTests.cs`
- `backend/RentFlow.Api.Tests/Services/MaintenancePhotoEvidenceServiceTests.cs` (new)
- `backend/RentFlow.Api.Tests/Services/MaintenanceCoordinationAgentClientTests.cs`
- `backend/RentFlow.Api.Tests/Services/MaintenanceCoordinationOrchestratorTests.cs`
- `backend/RentFlow.Api.Tests/Services/MaintenanceCoordinationServiceTests.cs`

React and report:

- `web/rentflow-web/src/features/maintenance/components/AiCoordinationCard.jsx`
- `web/rentflow-web/src/features/maintenance/services/maintenanceCoordinationResult.js`
- `web/rentflow-web/src/features/maintenance/maintenanceCoordinationUi.test.jsx`
- `docs/maintenance-coordination-phase3-report.md` (this report)

## 15. Python focused and full tests

Focused maintenance/vision: **199 passed** (36 new photo cases plus 163 existing cases).
Full pytest: **344 passed**. All model/vision calls use fakes, with the existing external
network guard. Coverage includes JPEG/PNG/WEBP, zero/multiple/irrelevant/unreadable/partial
photos, content spoofing, dimensions, metadata, conflicts, image instructions, strict output,
literal review, correlation/contract bounds, unavailable vision, safe errors/debug logs,
service authentication and shared/optional budgets. One existing Google SDK Python 3.14
deprecation warning remains.

Commands, from `agent`:

```text
python -m pytest tests/test_maintenance_photo_evidence.py tests/test_maintenance_coordination.py -q -p no:cacheprovider --basetemp=../.tmp/phase3-python-focused-final
python -m pytest -q -p no:cacheprovider --basetemp=../.tmp/phase3-python-full-final
```

## 16. Backend focused and full tests

Focused media/coordination/authorization/attachment regressions: **550 passed**.
New image service cases: **19 passed**, including real decoders, excessive PNG headers,
metadata/orientation, resize/encoding retry, per-image and aggregate bounds, deterministic
selection, authorized private retrieval, partial/all failures and cancellation/sub-budgets.
HTTP tests cover both existing analysis actions across owning/other Landlord, Admin, Tenant
and Technician, with retrieval counters, payload privacy and safe persisted counts.
Full backend suite: **1,480 passed, 16 skipped** (1,496 total). The skips require an explicit
disposable PostgreSQL test database; no development database was used. Backend Release
build passed with **0 warnings, 0 errors**.

```text
dotnet test backend/RentFlow.Api.Tests/RentFlow.Api.Tests.csproj --no-restore --filter 'FullyQualifiedName~MaintenancePhotoEvidence|FullyQualifiedName~MaintenanceCoordination|FullyQualifiedName~MaintenanceRequestsAuthorization|FullyQualifiedName~MaintenanceAttachment' --logger 'console;verbosity=minimal' --verbosity quiet
dotnet test backend/RentFlow.Api.Tests/RentFlow.Api.Tests.csproj --no-restore --logger 'console;verbosity=minimal' --verbosity quiet
dotnet build backend/RentFlow.Api/RentFlow.Api.csproj --no-restore --configuration Release --verbosity quiet
```

## 17. React tests, lint and build

Focused maintenance tests: **64 passed in 3 files**, including 52 AI card cases.
Full web suite: **645 passed in 56 files**. ESLint and production build passed.
Counts are tested for singular/full/partial/zero analysis, missing/malformed/private metadata,
with the existing recommendation/action/race/reload tests retained. The existing Vite
chunk-size warning remains (main JavaScript about 793 kB minified).

Commands, from `web/rentflow-web`:

```text
npm.cmd run test -- src/features/maintenance/maintenanceCoordinationUi.test.jsx src/features/maintenance/maintenanceWorkflow.test.jsx src/features/maintenance/services/maintenanceEnums.test.js
npm.cmd run test
npm.cmd run lint
npm.cmd run build
```

## 18. Diff check and branch

Source `git diff --check` passed, with no whitespace errors. Branch remains
`feature/full-app-polish`. Existing LF/CRLF notices are informational. The five pre-existing
inaccessible tracked pytest-temp deletions were left untouched; checks exclude those temp
paths. Newly added files are also checked directly for whitespace. No staging, commits,
pushes, PRs, branch changes or migrations were performed.

## 19. Remaining limitations

Real provider quality/latency and production R2 connectivity were not exercised; this work
uses real image decoders and fake network/model boundaries. Photos are supporting evidence,
and prompts/strict schemas cannot guarantee a model will interpret pixels correctly or
resist every image instruction. Metadata removal does not remove identity/contact/location
information visibly present in pixels; recognizable contact redaction in text remains best
effort. Exact causes, safety/compliance, repair quality/cost and technician competence require
human evidence/review. Animated files contribute their first frame only; resized images can
lose fine detail. CPU decode/resize cancellation is cooperative with fixed work bounds,
rather than forcibly terminating native processing. Failed optional phases fall back within
available time; mandatory text or exhausted total deadlines can still fail advisory analysis.
Counts are snapshots of selected evidence, so later attachment changes require a new run.
SixLabors.ImageSharp 3.1.12 is the new image-processing dependency; its publisher's
[package/license documentation](https://www.nuget.org/packages/SixLabors.ImageSharp/3.1.12)
is linked in backend setup. Existing PostgreSQL skips and bundle-size warnings remain.

## 20. Readiness for Phase 4 repair-information validation

Phase 3 provides the private evidence preparation, strict derived visual assessment,
stable final recommendation contract, safe counts, failure handling and human review
boundaries needed for Phase 4. The existing bounded latest repair estimate already enters
the text contract. Phase 4 can validate repair scope/explanation against text and available
visual evidence within this architecture, while preserving existing estimate approval and
maintenance state transitions. No Phase 4 repair-quality certification or autonomous action
was added here.
