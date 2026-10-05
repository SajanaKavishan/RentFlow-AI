# Maintenance Coordination Agent ? Phase 2 report

Implemented on `feature/full-app-polish`. No commit, push, PR, or branch operation was performed.

## 1. Previous presentation

The Landlord Maintenance page showed workflow IDs/statuses, plan/execution summaries, and the raw finalResultJson string in its activity sidebar. Saved runs depended on a localStorage workflow lookup ID because there was no server-side latest-run endpoint.

## 2. Final card structure

A separate AiCoordinationCard now appears in selected request detail after the description/access/other existing notes and before the human Request actions section.

The card contains:

- AI Coordination heading and advisory support copy.
- Human review required badge for a valid structured recommendation.
- Suggested category and priority rows with separate confidence labels.
- Required work category and explanatory technician-skill copy.
- Recommended next step and deterministic responsible actor.
- Readable validation considerations and uncertainty/emergency callouts.
- Plain-text ?Why the AI suggested this? rationale.
- Optional review notes, Reject recommendation, and Accept recommendation.
- Run again and, while the request is Submitted, an optional draft-only triage prefill.

Reviewed runs show compact accepted/rejected state and remove final-decision buttons.

## 3. Category, priority, and confidence

Canonical category values receive friendly labels, including HVAC / A/C and Locks / Doors. Public numeric maintenance values remain unchanged. Shared display labels also improve the matching maintenance detail/triage labels.

Priorities remain Low, Normal, High, Emergency. Null suggestions show Insufficient information.

Confidence is displayed as High confidence, Medium confidence, Low confidence, or Confidence unknown. No percentages are invented. Low/Unknown evidence receives explicit uncertainty copy. Recommendation surfaces use pale olive; attention uses amber; safety/error states use restrained red.

## 4. Required work

recommendedTechnicianCategory renders as ?[friendly category] maintenance? or More information needed. Supporting copy states that individual technician skills must be checked separately. No particular technician, verified skill, ranking, workload, availability, or distance is inferred.

## 5. Next-action mapping

| Structured action | Display text | Responsible |
|---|---|---|
| triage | Review and triage the request | Landlord / Admin |
| assign-technician | Assign a maintenance technician | Landlord / Admin |
| estimate-pending | Request a repair estimate | Landlord / Admin |
| submit-estimate | Technician should submit an estimate | Technician |
| submit-for-review | Submit the estimate for landlord review | Technician |
| review-estimate | Review the submitted estimate | Landlord / Admin |
| start-work | Technician can start approved work | Technician |
| complete-work | Technician can complete the work when finished | Technician |
| null | No AI workflow action suggested | No action |

These are display mappings of Phase 1?s closed action contract. The card does not execute an action or ask the model to choose an actor.

## 6. Validation flags

| Code | Primary UI label |
|---|---|
| InsufficientInformation | More information may be needed |
| CategoryDescriptionMismatch | Check the selected category |
| EstimateExplanationMissing | The estimate needs more detail |
| EstimateScopeMismatch | Check the scope of the estimate |
| PhotoUnavailable | Photos were not analyzed |
| PhotoUnreadable | Photo information is unclear |
| UrgencyNeedsHumanReview | Urgency needs human review |

Each flag retains its bounded backend message as text. Informational photo flags are neutral, ordinary attention flags amber, and urgency warnings red. Raw code names are not primary UI.

## 7. Human review and safe parsing

The UI parser checks required fields, exact canonical enum/confidence/action/flag membership, bounded rationale/messages, literal requiresHumanReview true, and the workflow/request relationship. Unknown result fields are rejected except the existing server-owned agentVersion and decisionDetails members.

Malformed, incompatible historical, or unsafe results receive an analysis-unavailable state. There is no raw JSON fallback. Rationale and messages use escaped React text; HTML/Markdown are not interpreted.

A review can be submitted only for the existing AwaitingHumanReview/Pending state with the backend human-approval requirement. Emergency recommendations, and an existing human Emergency priority, show explicit human safety-review copy.

## 8. Analyze, loading, error, retry

Analysis remains explicit and on demand. Initial page/detail loading only reads existing workflow state.

During analysis, progress is contained inside the card; eligible maintenance controls remain available. Synchronous guards prevent repeated clicks. Refreshing or reselecting a request joins its in-flight operation, preventing a second analysis POST. Late responses cannot attach another request?s recommendation to the current detail.

Running saved workflows offer Check progress through a read-only lookup. Failed/malformed runs show AI analysis unavailable, explain that normal maintenance management remains available, and offer Try again. Provider errors, stack traces, internal URLs, and raw workflow diagnostic fields are not rendered.

## 9. Accept/reject semantics

Accept recommendation and Reject recommendation retain the existing workflow approval/rejection PATCH endpoints. Optional review notes are submitted through that contract.

The returned API workflow state determines the outcome. Accepted shows Recommendation accepted; rejected shows Recommendation rejected. The UI never assumes a decision succeeded merely because a button was clicked. Reviewed states remove active decision buttons.

Review failure preserves the recommendation and uses safe generic retry copy.

## 10. No automatic business action

Analysis and recommendation decisions update only AI workflow UI state. They do not invoke maintenance triage, assignment, estimate approval/rejection, start work, or completion.

The optional Use suggestion in triage button fills category/priority drafts only after an explicit click. It makes no API mutation. A human Emergency selection is kept when AI proposes a lower priority. The landlord must submit the normal triage action separately.

Tests verify no automatic maintenance writes, unchanged actual priority before prefill, separate decision endpoints, and continued human-control availability.

## 11. Latest workflow retrieval

Added:

`GET /api/maintenance-requests/{requestId}/coordination-workflows/latest`

- Existing Phase 1 request/property authorization runs first.
- Owning Landlord allowed; another Landlord forbidden.
- Existing Admin scope preserved; Tenant/unauthenticated reads denied.
- 204 when an authorized existing request has no run.
- 200 with MaintenanceCoordinationWorkflowResponseDto otherwise.
- Results ordered by CreatedAt descending, then Id descending for deterministic ties.
- AsNoTracking retrieval and private, no-store cache policy.
- No AI invocation and no EF navigation objects in responses.

Updating/reviewing an older run does not promote it ahead of a newer-created run. Accepted/rejected latest states survive retrieval.

## 12. localStorage

Maintenance workflow lookup no longer reads or writes localStorage. Reloads query the server. Old local lookup entries are ignored and do not need deletion. Existing application authentication/storage behavior is unchanged.

Successful analysis uses its authoritative POST response directly, avoiding an unnecessary duplicate detail request.

## 13. Files changed

Backend:

- backend/RentFlow.Api/Controllers/MaintenanceRequestsController.cs
- backend/RentFlow.Api/Services/Interfaces/IMaintenanceCoordinationOrchestrator.cs
- backend/RentFlow.Api/Services/MaintenanceCoordinationOrchestrator.cs
- backend/RentFlow.Api.Tests/Controllers/MaintenanceRequestsAuthorizationTests.cs

React:

- web/rentflow-web/src/features/maintenance/pages/LandlordMaintenancePage.jsx
- web/rentflow-web/src/features/maintenance/components/AiCoordinationCard.jsx (new)
- web/rentflow-web/src/features/maintenance/components/ai-coordination.css (new)
- web/rentflow-web/src/features/maintenance/services/maintenanceCoordinationResult.js (new)
- web/rentflow-web/src/features/maintenance/services/maintenanceApiService.js
- web/rentflow-web/src/features/maintenance/services/maintenanceEnums.js
- web/rentflow-web/src/features/maintenance/maintenance.css
- web/rentflow-web/src/features/maintenance/maintenanceWorkflow.test.jsx
- web/rentflow-web/src/features/maintenance/maintenanceCoordinationUi.test.jsx (new)

Documentation:

- docs/maintenance-coordination-phase2-report.md (new)

No Python, Flutter, database migration, dependency, photo-analysis, or business-transition change was made.

## 14. React verification

- Final focused maintenance UI/workflow/enum tests: 51 passed.
- Final full web suite: 632 passed across 56 files.
- Coverage includes empty/loading/error/retry, all action/flag labels, null uncertainty, emergency warnings, accepted/rejected retrieval, plain-text injection safety, draft-only prefill, keyboard activation, late-request isolation, and refresh during analysis.
- Tests use mocked ASP.NET responses; no live model calls.

## 15. Backend verification

- Focused maintenance coordination/retrieval/authorization suite: 506 passed.
- Full backend suite: 1,445 passed, 16 skipped, zero failures.
- PostgreSQL-only tests skipped because no disposable test connection was configured.
- Retrieval tests cover ownership, Admin/Tenant/unauthenticated behavior, empty response, deterministic ordering, retained decisions, safe DTOs, and zero agent invocations.

## 16. Lint, builds, and browser checks

- npm lint: passed.
- npm build: passed; Vite reports the application bundle exceeds its 500 kB warning threshold. Code splitting was not added in this phase.
- Backend Release build: passed, zero warnings/errors.
- Headless Chrome verified the full page at 390, 768, 1280, and 1600 pixel viewport widths, with no horizontal overflow.
- Recommendation rows adapt to actual card width, including narrow laptop columns; rationale/flags wrap.
- Running/failure browser checks retain normal triage actions.
- Buttons/inputs have visible focus styles, real button semantics, textual confidence/flags, and announced loading/review states.
- Selected request, AI card, and rationale use h2/h3/h4 hierarchy.

Browser validation used controlled API test fixtures and blocked external requests. Screenshots are local test artifacts under .tmp/maintenance-phase2-visual, not live AI results.

## 17. Diff check and branch

git diff --check passed for changed source. The pre-existing inaccessible tracked agent test-temp paths were excluded from the source check; their five existing deletions were left untouched. Git also emits normal LF/CRLF conversion notices for some existing files.

Branch remains feature/full-app-polish. No commit, push, PR, or branch operation was performed.

## 18. Remaining limitations

- No reliable complete input snapshot/fingerprint is persisted, so no automatic stale-analysis indicator is fabricated. Run again remains available after request changes.
- Historical pre-Phase-1 result shapes are safely unavailable and require a new analysis.
- Only the latest run is recovered; a full workflow-history UI was intentionally omitted.
- Actual AI availability still depends on Phase 1 service credentials/provider configuration.
- No maintenance image bytes are retrieved or analyzed.
- Admin API access is retained, but this phase does not broaden the existing Landlord-only web route.
- PostgreSQL-only checks require the project?s disposable test database.

## 19. Phase 3 readiness

The landlord review UI and server recovery contract are ready for Phase 3 work. Private bounded photo retrieval/analysis can extend the existing authenticated service boundary and use the current photo consideration labels. Photo analysis itself remains unimplemented, and human authority remains mandatory.
