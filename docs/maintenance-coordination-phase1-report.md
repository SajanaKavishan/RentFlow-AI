# Maintenance Coordination Agent ? Phase 1 report

Implemented on `feature/full-app-polish`. No commit, push, PR, or branch operation was performed. The existing FastAPI service, maintenance endpoints, six-step graph, and workflow tables remain in use.

## 1. Canonical input contract

The internal request contains:

- `maintenanceRequestId`: request UUID.
- `title`: trimmed/redacted, at most 200 characters.
- `description`: trimmed/redacted, at most 4,000 characters.
- `category`, `priority`, `currentStatus`: exact canonical enum names.
- `preferredAccessWindow`: Morning, Afternoon, Evening, or null for legacy records.
- `hasAssignedTechnician`: boolean derived from the assignment.
- `attachments`: up to five metadata records containing only attachmentId, contentType, and fileSize.
- `repairEstimate`: null or the latest estimate with versionNumber, laborCost, partsCost, additionalCost, totalCost, notes, and status.

Tenant identity/contact fields, user JWTs, technician identity/contact, property address, access notes, filenames, uploader IDs, storage keys, signed URLs, and image bytes are absent.

Attachment MIME values are JPEG, PNG, WEBP; the metadata size limit matches the existing 10 MiB upload limit. Estimate notes accept 4,000 characters. Costs use Python Decimal validation with non-negative finite values and no artificial ceiling below valid backend amounts.

## 2. Canonical result contract

Successful results contain all these fields, including nullable fields explicitly:

```text
suggestedCategory: canonical category | null
categoryConfidence: High | Medium | Low | Unknown
suggestedPriority: canonical priority | null
priorityConfidence: High | Medium | Low | Unknown
recommendedTechnicianCategory: canonical category | null
nextAction: supported action | null
validationFlags: [{code: allowed flag, message: bounded string}]
rationale: nonblank string, maximum 3000 characters
requiresHumanReview: literal true
agentVersion: server-owned version, maximum 100 characters
```

Flags are limited to 50 items, each with a nonblank message of at most 1,000 characters. Allowed codes are InsufficientInformation, CategoryDescriptionMismatch, EstimateExplanationMissing, EstimateScopeMismatch, PhotoUnavailable, PhotoUnreadable, and UrgencyNeedsHumanReview.

Missing category/priority suggestions require Low or Unknown confidence. Technician category describes required work; it establishes no particular person's skill.

The HTTP response retains maintenanceRequestId, result, and executionMetadata. Execution metadata must identify the six actual graph steps in order.

## 3. Enum and status alignment

Categories: Plumbing, Electrical, Appliance, Structural, Security, Pest, Other, Hvac, LocksDoors.

Priorities: Low, Normal, High, Emergency.

Statuses: Submitted, Triaged, Assigned, EstimatePending, EstimateSubmitted, AwaitingLandlordApproval, Approved, Rejected, InProgress, Completed, Cancelled.

Python uses closed string enums with exact values. Lowercase legacy category values, medium, urgent, open, and on_hold are rejected. ASP.NET uses canonical names internally; existing public maintenance numeric enum serialization is unchanged.

## 4. Shared request mapper

`MaintenanceCoordinationRequestMapper` now supplies both ephemeral and persisted analysis. It validates enum membership, bounds/trims text, redacts recognizable email addresses, URLs, and phone-like strings, omits private fields, and preserves estimate detail.

Tests compare payloads from both real service paths for every status and cover all category/priority/status combinations. Redaction is best-effort; arbitrary personal names and every possible PII format cannot be detected reliably.

## 5. State-valid next actions

| Request status | Permitted non-null suggestion |
|---|---|
| Submitted | triage |
| Triaged | assign-technician |
| Assigned | estimate-pending |
| EstimatePending | submit-estimate |
| EstimateSubmitted | submit-for-review |
| AwaitingLandlordApproval | review-estimate |
| Approved | start-work |
| InProgress | complete-work |
| Completed / Rejected / Cancelled | None |

Null is an explicit abstention in any state. Closed states require null.

Python validates the coordination and final summary actions. ASP.NET independently validates the action and exact enum/confidence/flag membership. Both backend paths reread request status after analysis and reject results if it changed during execution.

## 6. Human-in-the-loop enforcement

Python requires literal boolean true for requiresHumanReview; false and numeric 1 are invalid. ASP.NET validates the same requirement. Successful persisted runs stop at AwaitingHumanReview.

Emergency input or suggested Emergency priority gets an explicit UrgencyNeedsHumanReview flag. Null suggestions receive an InsufficientInformation flag.

AI analysis and accepting/rejecting its review never invoke triage, assignment, estimate decisions, start work, or completion. Integration tests confirm status, category, priority, and technician assignment remain unchanged after AI decisions.

## 7. Landlord property authorization

Maintenance resource access uses the existing IPropertyAccessGuard with the authenticated user's ID.

Landlords must own the request's property for detail, history, estimates, property collections, manager actions, and all coordination endpoints. Another landlord receives 403 before business operations or agent invocation. Admin access retains its existing role-based scope. Tenant ownership and assigned-technician checks remain enforced.

Caller-supplied landlord IDs do not establish authority.

## 8. Technician assignment validation

Before modifying a request, the assignment service verifies the candidate exists, is active, and has the MaintenanceTechnician role. Inactive, wrong-role, and nonexistent IDs fail validation without changing status, assignment, or history. Active technician assignment remains a human action.

No technician ranking, skills, availability, workload, or distance model was introduced.

## 9. Service-to-service authentication

All Python /internal/* routes validate X-RentFlow-Service-Key using constant-time comparison. Missing/wrong credentials receive 401; missing server configuration fails closed with 503. Health remains publicly accessible.

All four ASP.NET agent clients use the shared service request helper. Maintenance additionally rejects missing or malformed credential configuration before making HTTP requests. User JWTs are not forwarded.

Configure the same private value on both services:

- Python environment or agent/.env: `AGENT_SERVICE_API_KEY`.
- ASP.NET environment: `AgentService__ServiceApiKey`, or secure configuration under `AgentService:ServiceApiKey`.

The checked-in examples contain blank values, not real credentials. Existing local secret files were not edited. Run the service over loopback, a private network, or appropriately protected transport. Deploy/restart Python and ASP.NET together because the internal maintenance contract changed.

## 10. Prompt-injection and data boundaries

Every maintenance model invocation identifies descriptions, notes, and file/image content as untrusted evidence, instructs the model to ignore embedded instructions, prohibits actions, and requests only the defined schema. It prohibits invented technician capabilities and claims of image inspection or repair-quality proof.

Groq already uses separate system/user messages. Gemini now sends trusted instructions through the SDK's system_instruction and input data through contents, for both existing adapter methods. Fake SDK tests verify separation.

Authorization and semantic validation remain independent of prompt wording.

## 11. Estimate fixes

The mapper preserves version, the three cost components, total, notes, and estimate status. Python accepts backend-length notes and amounts beyond the previous ten-million cap. Currency was removed because it is not persisted on RepairEstimate; neither arbitrary USD nor LKR is supplied.

No estimate business rule, financial approval action, or estimate persistence schema changed.

## 12. Timeout and cancellation behavior

The maintenance Python route wraps the entire six-call graph in one asyncio deadline. Its budget is capped by AI_TIMEOUT_SECONDS, 30 seconds, and the backend's supplied X-RentFlow-Analysis-Budget-Seconds.

The HTTP client reserves a second inside its configured overall deadline, with a small positive floor for a one-second test budget. The persisted orchestrator additionally links all execution to one configured total timeout and caller cancellation.

Timeouts and failures produce safe analysis errors. Persisted aborted runs become Failed, active steps become Failed, and cleanup saves with a non-cancelled token. Caller cancellation is rethrown after cleanup. Failed runs require no recommendation approval and retain no final recommendation. Underlying maintenance fields remain unchanged.

Process termination or database unavailability can still prevent durable cleanup; this phase does not add a recovery worker.

## 13. Persistence and DTO behavior

Existing MaintenanceCoordinationWorkflow and MaintenanceCoordinationStep tables are reused. No migration, new table, category/priority overwrite, or autonomous business action was added.

Human decisions are recorded in a separate decisionDetails JSON member without replacing the original recommendation fields. Approve/reject endpoints now return MaintenanceCoordinationWorkflowResponseDto consistently with creation/retrieval, avoiding EF navigation cycles.

Historical stored results are retained; Phase 2 must handle their older field shape.

## 14. Files changed

Python production/configuration:

- agent/.env.example
- agent/app/config.py
- agent/app/main.py
- agent/app/api/routes.py
- agent/app/schemas/maintenance.py
- agent/app/agents/maintenance_nodes.py
- agent/app/services/gemini_provider.py

Backend production/configuration:

- backend/RentFlow.Api/Configuration/AgentServiceOptions.cs
- backend/RentFlow.Api/appsettings.json
- backend/RentFlow.Api/Controllers/MaintenanceRequestsController.cs
- backend/RentFlow.Api/DTOs/Maintenance/MaintenanceCoordinationAgentContracts.cs
- backend/RentFlow.Api/Services/AgentServiceRequest.cs (new)
- backend/RentFlow.Api/Services/MaintenanceCoordinationRequestMapper.cs (new)
- backend/RentFlow.Api/Services/MaintenanceCoordinationResultValidator.cs (new)
- backend/RentFlow.Api/Services/MaintenanceCoordinationService.cs
- backend/RentFlow.Api/Services/MaintenanceCoordinationOrchestrator.cs
- backend/RentFlow.Api/Services/MaintenanceCoordinationAgentClient.cs
- backend/RentFlow.Api/Services/MaintenanceRequestService.cs
- backend/RentFlow.Api/Services/ApplicationValidationAgentClient.cs
- backend/RentFlow.Api/Services/PropertyMatchingAgentClient.cs
- backend/RentFlow.Api/Services/PricingAnalysisAgentClient.cs

Tests:

- agent/tests/conftest.py
- agent/tests/test_api.py
- agent/tests/test_gemini_provider.py
- agent/tests/test_maintenance_coordination.py
- agent/tests/test_pricing_analysis.py
- backend/RentFlow.Api.Tests/Authentication/TechnicianMaintenanceContactTests.cs
- backend/RentFlow.Api.Tests/Controllers/MaintenanceCoordinationWorkflowResponseTests.cs
- backend/RentFlow.Api.Tests/Controllers/MaintenanceRequestsAuthorizationTests.cs
- backend/RentFlow.Api.Tests/Services/MaintenanceCoordinationAgentClientTests.cs
- backend/RentFlow.Api.Tests/Services/MaintenanceCoordinationOrchestratorTests.cs
- backend/RentFlow.Api.Tests/Services/MaintenanceCoordinationServiceTests.cs
- backend/RentFlow.Api.Tests/Services/MaintenanceRequestServiceTests.cs
- backend/RentFlow.Api.Tests/Services/MaintenanceCoordinationRequestMapperTests.cs (new)
- backend/RentFlow.Api.Tests/Services/MaintenanceCoordinationTestData.cs (new)

Documentation:

- agent/README.md
- docs/maintenance-coordination-phase1-report.md (new)

React/Flutter source, database migrations, and model dependencies were not changed.

## 15. Python verification

- Maintenance-only focused suite: 163 passed.
- Final focused maintenance + Gemini adapter suite: 176 passed.
- Final full pytest suite: 308 passed.
- compileall for app: passed.
- No Python lint configuration was found.
- One existing google-genai deprecation warning occurs on this Python 3.14 installation.
- Fake model/SDK clients and the existing external-network guard were used; no live provider calls.

Pytest basetemp was redirected to workspace .tmp directories to avoid pre-existing inaccessible test-temp directories.

## 16. Backend verification

- Final focused coordination, authorization, assignment, and technician contact suite: 577 passed.
- Final full backend suite: 1,441 passed, 16 skipped, zero failures.
- PostgreSQL-only tests skipped because the disposable test connection was not configured.
- HTTP contract tests use stub handlers; controller tests inject fake agent clients.

An older contact-privacy fixture was adjusted to create an owned property for its landlord; its contact-redaction assertion remains intact.

## 17. Builds and diff checks

- Backend Debug build: passed, zero warnings/errors.
- Final Backend Release build: passed, zero warnings/errors.
- React maintenance workflow/enum regressions: 12 tests passed.
- Agent compilation: passed.
- git diff --check on changed source: passed; inaccessible pre-existing tracked test-temp paths were excluded from that check.
- Branch remains feature/full-app-polish.

The five pre-existing tracked temporary-test deletions were left untouched.

## 18. Remaining limitations

- Shared credentials must be configured privately before internal AI routes can be used.
- Text redaction is conservative and incomplete, with possible false positives.
- Provider output/protocol behavior was verified with fakes, not live services.
- No photo bytes are retrieved or analyzed; PhotoUnavailable explicitly identifies metadata-only inputs.
- No technician specialty, scheduling, ranking, or availability feature exists.
- Existing historical result JSON may have the previous contract.
- Status is checked after analysis; full input fingerprinting and stale-card UX remain later work.
- Cleanup requires a functioning process/database.
- PostgreSQL integration checks need the project's disposable test database.

## 19. Phase 2 readiness

The text contracts, resource authorization, service credential boundary, human-review requirement, state-aware validation, and failure paths are implemented and regression-tested. Phase 2 can build the readable AI Coordination card on this contract after configuring both service credentials. The existing raw-result UI remains in place for this phase. Photo analysis remains Phase 3.
