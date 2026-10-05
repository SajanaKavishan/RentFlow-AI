# RentFlow AI application-validation agent

This directory contains the private Python foundation for AI-assisted application
analysis. It uses FastAPI, LangGraph, and strict Pydantic schemas. The service does
not make rental decisions: it organizes supplied facts into a concise summary for a
landlord, and every successful result requires human approval.

## Architecture boundary

ASP.NET Core remains RentFlow's only public application API and owns authentication,
authorization, business rules, PostgreSQL persistence, document access, deterministic
validation, rental decisions, and human approval. ASP.NET calls this service over a
private service-to-service route only after its deterministic steps complete.

React and Flutter must never call this service directly. This service never connects
to PostgreSQL or Cloudflare R2 and accepts neither credentials nor arbitrary tools.
ASP.NET may also send bounded PDF/JPEG/PNG content as Base64 after it performs application
authorization and private R2 retrieval. Python receives no storage key, URL, credential,
or database access. Phase B decodes content in memory, extracts selectable PDF text with
`pypdf`, and uses bounded vision OCR for scanned PDFs and images. It never writes extracted
text or document media to permanent files.

## Workflow

`POST /internal/application-validation/analyze` invokes a fixed LangGraph:

1. `plan` validates the one allow-listed plan.
2. `analyze_application_data` describes completeness and visible inconsistencies.
3. `analyze_document_metadata` checks metadata coverage, missing types, and duplicates.
4. `verify_supporting_documents` runs bounded hybrid extraction and allow-listed fact analysis.
5. `analyze_cross_document_consistency` performs deterministic conservative comparisons.
6. `analyze_consistency` compares existing structured inputs and authoritative findings.
7. `summarize_findings` returns one allowed landlord-review recommendation and attaches the
   structured document findings.

The state remains JSON serializable. Each model response is validated with its own
Pydantic schema. Hidden reasoning is neither requested nor returned; only concise
findings, explanations, warnings, recommendations, and execution metadata cross the
service boundary.

Allowed recommendations are:

- Ready for landlord review
- Request missing information
- Request missing documents
- Manual review required

Approval/rejection language and tenant risk scoring are not valid outputs.
`requiresHumanApproval` must always be `true`.

## Local setup

Python 3.11 or newer is required.

```powershell
cd agent
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8001
```

Health check:

```text
GET http://127.0.0.1:8001/health
```

ASP.NET calls the internal endpoint with only application data, document metadata,
and deterministic findings it has authorized and prepared:

```json
{
  "workflowId": "workflow-123",
  "applicationId": "application-456",
  "objective": "Summarize the application for landlord review.",
  "applicationData": {"employmentStatus": "employed"},
  "documentMetadata": [
    {
      "documentId": "document-789",
      "documentType": "proof_of_income",
      "fileName": "income.pdf",
      "isRequired": true
    }
  ],
  "deterministicFindings": [],
  "supportingDocuments": [
    {
      "documentId": "document-789",
      "documentType": "IncomeProof",
      "originalFileName": "income.pdf",
      "contentType": "application/pdf",
      "sizeBytes": 4,
      "contentBase64": "JVBERg=="
    }
  ]
}
```

Supporting-document inputs reject unknown fields, malformed Base64, decoded size above
5 MiB, mismatched `sizeBytes`, unsupported MIME types, and unsupported document types.
Output schemas allow only the narrow facts and comparisons documented in
`docs/application-validation-agent-integration.md`; sensitive identity data and all
tenant/trust/fraud/risk scores are absent.

## Configuration

Copy `.env.example` to `agent/.env` for local development. The service loads that
agent-root file automatically; real operating-system environment variables take
precedence. The `.env` file is ignored by Git and must never be committed:

- `AI_PROVIDER`: `groq` or `gemini` (Gemini aliases: `google`, `google-genai`)
- `AI_MODEL`: provider model identifier; development defaults to `openai/gpt-oss-20b`
- `GROQ_API_KEY`: Groq credential, used only when `AI_PROVIDER=groq`
- `GEMINI_API_KEY`: Gemini credential for either text or vision (`AI_API_KEY` remains a
  backwards-compatible alias)
- `VISION_PROVIDER` / `VISION_MODEL`: optional dedicated OCR/vision provider; when omitted,
  a vision-capable primary provider may be reused; a text-only primary fails safely to
  manual review without receiving image content
- `VISION_API_KEY`: optional dedicated vision credential; otherwise the matching primary key
  is reused
- `AI_TIMEOUT_SECONDS`: per-call timeout; defaults to 30
- `EXTRACTION_TIMEOUT_SECONDS`: whole-document extraction deadline; defaults to 20
- `MAX_PDF_PAGES`: maximum selectable-text/rendered pages; defaults to 5
- `MAX_EXTRACTED_CHARACTERS`: in-memory extracted-text cap; defaults to 50,000
- `MAX_MODEL_INPUT_CHARACTERS`: fact-analysis input cap; defaults to 20,000
- `INCOME_TOLERANCE_PERCENT`: monthly-income comparison tolerance; defaults to 5
- `AGENT_VERSION`: version returned in validated summaries; defaults to 0.1.0
- `AI_DEVELOPMENT_DIAGNOSTICS`: temporary sanitized node diagnostics; defaults to disabled

The service and `/health` start without AI configuration. Analysis then returns a
sanitized `provider_not_configured` error. No production response is faked. Groq uses
the official asynchronous Groq SDK with strict JSON Schema Structured Outputs for
`openai/gpt-oss-20b`; Gemini uses Google's supported `google-genai` SDK. Both paths
retain the full local Pydantic validation after provider output. Unsupported provider
names fail safely.

Digital PDFs with sufficient selectable text do not require `VISION_PROVIDER` or a vision
credential. Scanned PDFs and JPEG/PNG inputs require an explicitly vision-capable adapter;
otherwise that document is marked unavailable for analysis and sent to manual review while
the rest of the workflow continues.

Development Groq text plus Gemini vision configuration:

```text
AI_PROVIDER=groq
AI_MODEL=openai/gpt-oss-20b
GROQ_API_KEY=<deployment secret>
VISION_PROVIDER=gemini
VISION_MODEL=gemini-2.5-flash
GEMINI_API_KEY=<deployment secret>
```

Gemini remains available:

```text
AI_PROVIDER=gemini
AI_MODEL=gemini-2.5-flash
GEMINI_API_KEY=<deployment secret>
```

The ASP.NET client is configured separately with `AgentService:BaseUrl` and
`AgentService:TimeoutSeconds` (environment names `AgentService__BaseUrl` and
`AgentService__TimeoutSeconds`). It is not called during ASP.NET startup.

## Tests

```powershell
cd agent
python -m pytest
```

Tests use an in-memory fake provider, actively block external network connections,
and cover digital/scanned PDF routing, image OCR routing, limits, English/Sinhala and
handwriting confidence, fact allow-lists, provider failures, deterministic comparisons,
output safety, plan restrictions, and ordered graph execution.


## Maintenance coordination: service boundary and optional photos

The maintenance agent uses exact RentFlow category, priority, and request-status names,
closed structured recommendations, explicit human review, and state-valid advisory actions.
Both backend analysis paths use one minimum-data request mapper. Phase 3 adds optional
private maintenance photo evidence to the existing on-demand workflow; tenant submission
does not invoke AI. The Phase 1 final recommendation schema remains unchanged.

Every `/internal/*` endpoint now requires `X-RentFlow-Service-Key`. Configure the same secret
as Python `AGENT_SERVICE_API_KEY` and ASP.NET `AgentService__ServiceApiKey`. Keep it in private
environment/secret configuration; the examples intentionally leave it blank. Unconfigured
internal authentication fails closed. `GET /health` remains accessible.

Deploy/restart both services together for the changed maintenance contract. The maintenance
graph has one total deadline capped by the backend budget and local configuration. Human
acceptance/rejection records an advisory review only; normal maintenance actions remain
independent and available when analysis fails.

See [the Phase 1 implementation report](../docs/maintenance-coordination-phase1-report.md)
for contracts, exact files, verification, and remaining limitations.

ASP.NET authorizes property ownership/manager role before downloading private R2 objects.
It selects at most five JPEG/PNG/WEBP attachments from this request in creation/ID order,
validates real image content, rejects sources beyond 8192 pixels per side or 20 million
pixels, applies orientation, resizes to at most 1280 pixels per side, and copies only pixels
into metadata-free JPEG quality 80. If needed it retries once at 960 pixels/quality 65.
The analysis representation is limited to 512 KiB/image and 2 MiB aggregate (about 2.67 MiB
Base64 plus bounded request JSON). Source retrieval remains capped at 10 MiB per photo.

The internal request optionally adds `evidencePhotos: [{attachmentId, contentType,
mediaBase64}]` and closed `photoLimitations` codes. Only the service-authenticated backend
sends this contract. Python validates Base64, actual MIME/decode/dimensions/byte limits
again, normalizes without metadata, and uses the existing `ModelMedia` abstraction.
Raw media and correlation/storage identifiers never enter the text graph. One strict
`MaintenanceVisualEvidence` assessment runs before the existing six graph nodes; its bounded
observations are untrusted evidence. No extra result flags or provider stack were added.

The existing `VISION_PROVIDER`, `VISION_MODEL`, `VISION_API_KEY` settings select the optional
adapter using the established configuration/fallback rules. Zero photos is normal text-only
analysis. Unavailable vision/storage or unreadable photos preserve usable evidence and add
`PhotoUnavailable`/`PhotoUnreadable`; text/photo conflicts and safety concerns require human
review. A readable irrelevant photo counts as analyzed but supplies no visual category.
Unreadable photos do not count as analyzed. Counts describe this run's selected photos,
not necessarily the current attachment list after later uploads.

Backend retrieval/preparation uses at most min(8s, one quarter of its total deadline).
The backend forwards its remaining budget, while Python caps the entire optional phase plus
graph at min(AI_TIMEOUT_SECONDS, 30s, that budget). Vision uses at most min(6s, one quarter
of Python's budget); preparation plus vision uses at most min(8s, one third). Cancellation
propagates and mandatory text failure fails the advisory workflow safely.

Only normal final recommendations and safe counts/failure summaries are persisted. Counts
reuse the existing agent step's `ValidationSummary` and appear as optional `photoEvidence`
on the public workflow DTO. Image bytes, Base64, filenames, storage keys and URLs are never
stored in coordination workflows or exposed to React. No database migration is required.
See [the Phase 3 report](../docs/maintenance-coordination-phase3-report.md) and
[backend setup](../backend/RentFlow.Api/README-MaintenanceCoordination.md).


Maintenance Groq compatibility: nullable primitive/enum fields are projected to Groq's
union-type schema (including null in enums), while full local Pydantic validation is retained.
The fixed `plan` node now builds its allow-listed plan locally; the graph still executes six
steps but makes five text-model calls, plus at most one optional vision call. This avoids
model-generated plan names and reduces latency/cost without changing the final result contract.
