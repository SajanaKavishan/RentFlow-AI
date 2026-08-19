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
The current document node analyzes metadata supplied by ASP.NET; it performs no OCR or
file reads.

## Workflow

`POST /internal/application-validation/analyze` invokes a fixed LangGraph:

1. `plan` validates the one allow-listed plan.
2. `analyze_application_data` describes completeness and visible inconsistencies.
3. `analyze_document_metadata` checks metadata coverage, missing types, and duplicates.
4. `analyze_consistency` compares all structured inputs and authoritative deterministic findings.
5. `summarize_findings` returns one allowed landlord-review recommendation.

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
  "deterministicFindings": []
}
```

## Configuration

Copy `.env.example` values into your environment (the service does not load `.env`
files or commit secrets):

- `AI_PROVIDER`: `gemini` (aliases: `google`, `google-genai`)
- `AI_MODEL`: Gemini model identifier, for example `gemini-2.5-flash`
- `AI_API_KEY`: provider credential
- `AI_TIMEOUT_SECONDS`: per-call timeout; defaults to 30
- `AGENT_VERSION`: version returned in validated summaries; defaults to 0.1.0

The service and `/health` start without AI configuration. Analysis then returns a
sanitized `provider_not_configured` error. No production response is faked. With all
three AI settings present, the provider adapter uses Google's supported `google-genai`
SDK and Gemini structured output. Unsupported provider names fail safely.

The ASP.NET client is configured separately with `AgentService:BaseUrl` and
`AgentService:TimeoutSeconds` (environment names `AgentService__BaseUrl` and
`AgentService__TimeoutSeconds`). It is not called during ASP.NET startup.

## Tests

```powershell
cd agent
python -m pytest
```

Tests use an in-memory fake provider, actively block external network connections,
and cover request validation, plan restrictions, output safety, safe failures, and
ordered graph execution.
