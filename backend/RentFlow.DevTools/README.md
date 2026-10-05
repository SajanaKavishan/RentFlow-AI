# Local maintenance AI test data

This standalone development tool creates an owned sample property and two submitted maintenance
requests for an existing active Landlord. It also creates a synthetic Tenant, approved application,
accepted rental offer and current active lease so the existing Tenant creation/photo-upload flows
work normally. The API endpoints, authorization and real AI workflow remain unchanged.

Run from the repository root while using your local PostgreSQL development database:

```powershell
dotnet run --project backend/RentFlow.DevTools --configuration Release -- --development --landlord-email YOUR_LANDLORD_EMAIL --dry-run
dotnet run --project backend/RentFlow.DevTools --configuration Release -- --development --landlord-email YOUR_LANDLORD_EMAIL
```

The tool uses the backend appsettings, Development settings, the API project's User Secrets and
OS environment, in the same order as development configuration. Both DOTNET_ENVIRONMENT and
ASPNETCORE_ENVIRONMENT must be unset or Development. It refuses remote PostgreSQL hosts,
non-development environments and databases with production names. It never migrates or deletes
anything, resets account passwords, generates fake AI results, uploads storage objects, or invokes
providers. Creation runs in one transaction. Re-running reuses the same property and preserves
existing request/review states. The existing Landlord's account/password are untouched.

The synthetic Tenant has a random password whose hash is stored using the existing Identity
hasher. Its login is written to an ignored `.tmp/maintenance-demo-PROPERTYID.txt` file. Credentials,
connection passwords and service API keys are not printed to tool/provider logs. This Tenant is a
real local test account and its lease may participate in normal development background jobs.

To test actual AI from the normal UI:

1. Start the backend, web frontend, and Python agent with matching service keys and configured
   Groq/Gemini keys. Keep the agent's existing private service authentication enabled.
2. Log in to the normal web app as the Landlord whose email you supplied.
3. Open Maintenance, select **[DEV] Maintenance AI test apartment**, and select either sample request.
   The tool also prints the property-scoped UI path for a direct link.
4. Click **Analyze request**. This runs the real backend/Python/model workflow and persists its
   actual advisory result. No seeded recommendation is substituted; API usage is incurred.
5. Test review acceptance/rejection or explicit triage separately, using the normal UI controls.

For actual photo analysis, open a separate browser profile/private window and log in with the
synthetic Tenant credentials. Select the current test property, create a maintenance request with
JPEG/PNG/WEBP photos using the ordinary form, then open that request as the Landlord and analyze.
This exercises the real private upload, R2 retrieval, preparation, vision provider and human review
flow. Use non-sensitive sample photos. Source and payload limits remain the Phase 3 limits.
The two automatically created requests are text-only until normal attachments are added.

No special production route, fake authentication token, public image URL or browser-visible
service key is introduced. The standalone tool is separate from the API and the frontend bundle.
Fixture tests cover local-development guards, dry-run safety, account-role checks, complete fixture
relationships and idempotency. Full maintenance behavior remains covered by existing API tests.
