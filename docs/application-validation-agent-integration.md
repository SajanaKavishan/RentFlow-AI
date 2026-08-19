# Application validation agent integration

ASP.NET Core remains the only public API. Its application-validation orchestrator runs
three authoritative deterministic steps before making one private HTTP call to the
Python service:

1. Application Data Validator
2. Document Validation Agent
3. Deterministic Rule Checker
4. Agentic Application Review

The fourth step sends a deliberately bounded contract: authorized application fields,
document metadata, normalized deterministic findings, and eligible supporting-document
content encoded as Base64. `IApplicationDocumentContentService` retrieves each private
object through `IFileStorageService`, verifies that it belongs to the current application,
allow-lists its type and MIME type, and applies a bounded read before creating the internal
payload. It never sends a Cloudflare R2 storage key, bucket credential, public URL, signed
URL, database credential, or arbitrary tool.

The private document flow is:

```text
private Cloudflare R2 object
    -> ASP.NET authorization and bounded retrieval
    -> Base64 in the private ASP.NET-to-Python request
    -> strict Python validation and Phase A structured findings
```

Python does not access R2 or PostgreSQL directly. Keeping authorization, object lookup,
size enforcement, and persistence in the authoritative ASP.NET service prevents storage
identifiers and credentials from crossing into the agent runtime. React and Flutter never
receive this internal payload.

Configure the analysis boundary with `DocumentAnalysis:Enabled`,
`DocumentAnalysis:MaxFileBytes`, and `DocumentAnalysis:AllowedContentTypes`. The default
limit is 5,242,880 bytes (5 MiB), equal to—not greater than—the upload limit. Only PDF,
JPEG, and PNG content is accepted. A MIME, size, ownership, retrieval, or content-length
failure excludes that one document and adds a sanitized workflow warning; it does not fail
the whole rental validation workflow.

Configure ASP.NET with `AgentService:BaseUrl` and `AgentService:TimeoutSeconds`. In an
environment-variable deployment these become:

```text
AgentService__BaseUrl=http://agent:8001
AgentService__TimeoutSeconds=30
```

Configure the Python process separately:

```text
AI_PROVIDER=gemini
AI_MODEL=gemini-2.5-flash
AI_API_KEY=<deployment secret>
AI_TIMEOUT_SECONDS=30
```

No key belongs in source control. ASP.NET does not contact Python during startup, so it
can start while the agent is unavailable. An unavailable, timed-out, unsuccessful, or
malformed AI response produces a sanitized failed Step 4 while preserving the three
completed deterministic step results.

Only structured verification output is persisted. Base64 content, hidden model reasoning,
raw prompts, provider details, storage identifiers, and credentials are not stored.
Deterministic recommendations cannot be weakened by AI output; conflicts are
reconciled conservatively and receive a structured warning. Every successful workflow
still ends in `AwaitingHumanReview` with `RequiresHumanApproval = true`. Neither service
automatically approves or rejects a rental application.

## Supporting-document safety policy

Phase A defines transport, schemas, graph state, and deterministic fake nodes only. It
does not perform OCR, image analysis, or multimodal provider calls.

Allowed extracted facts are intentionally narrow:

- Income proof: applicant name, income amount, pay period, employer name, document date.
- Employment letter: applicant name, job title, employer name, document date.
- Identity document: applicant name, readability, and expected-category confirmation only.

Allowed consistency comparisons are occupation versus job title, monthly income versus
income amount, applicant-name consistency, employer-name consistency, and detected
category versus uploaded type. There is no tenant, trust, fraud, or risk score.

NIC/passport/birth-certificate numbers, date of birth, gender, religion, ethnicity,
disability, facial attributes, health data, political affiliation, sexual orientation,
and parent details are prohibited. Protected characteristics and tenant risk are never
inferred. All findings require landlord review and cannot approve or reject a tenant.

Real OCR/multimodal extraction, confidence calibration, and actual cross-document fact
comparison are deferred to Phase B and require an explicitly approved provider design.
