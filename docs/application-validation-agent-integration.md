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
    -> strict Python validation and bounded in-memory Phase B extraction
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
AI_PROVIDER=groq
AI_MODEL=openai/gpt-oss-20b
GROQ_API_KEY=<deployment secret>
VISION_PROVIDER=gemini
VISION_MODEL=gemini-2.5-flash
GEMINI_API_KEY=<deployment secret>
AI_TIMEOUT_SECONDS=30
EXTRACTION_TIMEOUT_SECONDS=20
MAX_PDF_PAGES=5
MAX_EXTRACTED_CHARACTERS=50000
MAX_MODEL_INPUT_CHARACTERS=20000
INCOME_TOLERANCE_PERCENT=5
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

## Phase B hybrid extraction

Digital PDFs are processed text-first with `pypdf` against an in-memory byte stream. Only
the configured first `MAX_PDF_PAGES` pages are read. When selectable text is insufficient,
those bounded pages are rendered in memory with `pypdfium2` and Pillow and sent through the
provider-neutral vision OCR boundary. Rendered pages are capped at 2,000 pixels on their
largest dimension. JPEG and PNG inputs go directly to that boundary.
No temporary or permanent extracted-text file is created.

The default limits are 5 PDF pages, 50,000 extracted characters, 20,000 model-input
characters, and a 20-second extraction deadline. Every truncation produces a safe warning.
The original 5 MiB transport limit remains authoritative. A dedicated vision provider/model
can be configured separately from the text-analysis provider. A text-only Groq model is not
treated as vision capable; missing/unsupported vision capability returns an unreadable,
unknown-confidence result and requires manual review. A vision provider/key is not required
when all submitted PDFs contain sufficient selectable text.

OCR classifies content as printed, handwritten, mixed, or unknown, and language as English,
Sinhala, mixed, or unknown. Printed English can be analyzed normally. Handwritten English
is analyzed only at sufficient confidence. Printed Sinhala is best-effort. Handwritten or
uncertain Sinhala is forced to low/unknown confidence, receives the warning "Handwritten
Sinhala text could not be verified reliably. Manual review is required.", and cannot create
a hard mismatch. Names are never automatically translated or transliterated.

## Supporting-document safety policy

Allowed extracted facts are intentionally narrow:

- Income proof: applicant name, income amount, pay period, employer name, document date.
- Employment letter: applicant name, job title, employer name, document date.
- Identity document: applicant name, readability, and expected-category confirmation only.

Allowed consistency comparisons are occupation versus job title, monthly income versus
income amount, applicant-name consistency, employer-name consistency, and detected
category versus uploaded type. There is no tenant, trust, fraud, or risk score.

The exact deterministic comparison rules are:

- Occupation/job title: trim, Unicode-safe lowercase/casefold, and collapse whitespace.
  Exact normalized equality is a match; shared-token differences are ambiguous warnings;
  otherwise medium/high-confidence differences are mismatches.
- Income: parse decimal values and normalize monthly, annual, weekly, and biweekly/fortnightly
  periods to monthly. The default tolerance is 5% of application monthly income and is
  configured with `INCOME_TOLERANCE_PERCENT`.
- Applicant name: Unicode NFKC normalization, casefolding, whitespace collapse, and
  punctuation removal. Cross-script Sinhala/English names are uncertain warnings, not hard
  mismatches. No biometric or facial comparison occurs.
- Employer: compare the income-proof and employment-letter names with the same conservative
  name normalization.
- Category: an exact selected/detected category is a match. Unknown or low-confidence output
  is a warning. A reliable different category records only the neutral finding "Uploaded
  content may not match the selected document type."

Low/unknown-confidence extraction is excluded from every hard mismatch. Any mismatch,
uncertainty warning, category concern, or per-document manual-review flag makes
`requiresManualReview` true. These findings can strengthen a ready recommendation to
`Manual review required`; they cannot weaken deterministic missing-information or
missing-document outcomes and can never approve or reject an application.

NIC/passport/birth-certificate numbers, date of birth, gender, religion, ethnicity,
disability, facial attributes, health data, political affiliation, sexual orientation,
and parent details are prohibited. Protected characteristics and tenant risk are never
inferred. All findings require landlord review and cannot approve or reject a tenant.

OCR/multimodal extraction and fact-analysis failures are isolated per document. Parser
errors, malformed output, rate limits, timeouts, and unsupported vision models return safe
warnings without raw provider details. The deterministic workflow result remains available
for landlord review.

Persisted document analysis contains only allow-listed structured facts, extraction method,
confidence, detected category, safe warnings, comparison findings, and manual-review flags.
Base64, full extracted text, raw prompts, hidden reasoning, storage keys, URLs, credentials,
and provider error bodies are never included in the result contract.
