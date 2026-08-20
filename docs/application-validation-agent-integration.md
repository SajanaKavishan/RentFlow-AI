# Application validation agent integration

ASP.NET Core remains the only public API. Its application-validation orchestrator runs
three authoritative deterministic steps before making one private HTTP call to the
Python service:

1. Application Data Validator
2. Document Validation Agent
3. Deterministic Rule Checker
4. Agentic Application Review

The fourth step sends a deliberately small contract: authorized application fields,
document IDs/types/file names/required flags, and normalized deterministic findings.
It never sends document bytes, Cloudflare R2 storage keys, database credentials, or
arbitrary tools.

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

Only structured AI output is persisted. Hidden model reasoning is not requested or
stored. Deterministic recommendations cannot be weakened by AI output; conflicts are
reconciled conservatively and receive a structured warning. Every successful workflow
still ends in `AwaitingHumanReview` with `RequiresHumanApproval = true`. Neither service
automatically approves or rejects a rental application.
