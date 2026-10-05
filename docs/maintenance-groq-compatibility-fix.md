# Maintenance Groq compatibility fix

Live development analysis failed at the AI step even though input validation and service-key
configuration passed. A synthetic live probe reproduced Groq HTTP 400 rejecting nullable enum
anyOf/$ref schemas. A separate probe also reproduced model-generated fixed plan steps that did
not match the strict allow-listed sequence.

The Groq adapter now projects nullable primitive fields and enum references to the documented
union-type representation, including null in nullable enums. This is a provider-facing schema
conversion only: local Pydantic canonical enums, confidence, human review, action rules, limits
and unknown-field rejection remain authoritative. Complex unions are left unchanged.
See [Groq Structured Outputs requirements](https://console.groq.com/docs/structured-outputs).

Maintenance's plan node now builds its existing fixed allow-listed plan locally, avoiding a
model call whose output cannot legitimately change the workflow. The six graph execution steps
and result contract remain unchanged. Text calls decrease from six to five; optional photos
still make at most one separate vision call. No automatic maintenance action was added.

Focused fake-provider checks passed (221 before the extra fixed-plan regression). Final full
Python suite passed: 346 tests, with the existing Google SDK deprecation warning. A synthetic
live Groq analysis passed with HTTP 200 and requiresHumanReview=true; the running agent endpoint
also returned 200. The backend-configured service key passed a no-model auth probe (422 invalid
body). No API keys/raw provider output were printed. Existing failed workflows were preserved;
the user must select Try again to create a fresh real advisory run.

The local development fixture tool gained read-only --inspect diagnostics for its existing
Landlord-owned test requests, safe workflow/step status and loopback agent authentication.
It does not execute analysis or modify workflows in inspection mode. Secret values are never
printed. Production API endpoints, resource authorization and maintenance DTOs are unchanged.
