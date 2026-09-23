# Maintenance Technician provisioning

Stage 2 adds an Admin-only backend workflow for creating a pending Maintenance Technician and letting that Technician set their initial password through a single-use token. It does not add a public staff registration path or any web/mobile UI.

## Security model

- Public `POST /api/auth/register` remains limited to `Tenant` and `Landlord`.
- The server always assigns `MaintenanceTechnician`; the provisioning request has no role field.
- The provisioning endpoint requires an Admin JWT and re-checks that the token subject is still an active `Admin` in the database. A JWT issued before deactivation or a role change is rejected.
- A 32-byte cryptographically random setup token is returned once in the successful Admin response. Only its SHA-256 digest is stored.
- Pending Technicians have no password hash and remain inactive, so normal login is rejected.
- Setup tokens expire after `StaffProvisioning:SetupTokenLifetimeMinutes` (60 minutes by default), are single-use, and are consumed in the same database save that hashes the password and activates the user. Optimistic concurrency on `ConsumedAt` permits only one concurrent activation to succeed.
- The anonymous activation endpoint is limited to five requests per source IP per minute.
- Passwords, raw setup tokens, password hashes, and JWTs are not logged.

## Endpoint contracts

### Create a pending Technician

`POST /api/admin/maintenance-technicians`

Authorization: `Bearer <Admin JWT>` using an active database Admin.

Request:

```json
{
  "fullName": "Maintenance Technician",
  "email": "technician@example.com",
  "phoneNumber": "+94770000001"
}
```

Success: `201 Created`

```json
{
  "id": "00000000-0000-0000-0000-000000000000",
  "fullName": "Maintenance Technician",
  "email": "technician@example.com",
  "phoneNumber": "+94770000001",
  "role": "MaintenanceTechnician",
  "isActive": false,
  "passwordSetupToken": "returned-once-secret",
  "passwordSetupExpiresAt": "2026-09-23T16:00:00+00:00"
}
```

The Admin must transfer `passwordSetupToken` to the intended Technician through an approved secure channel. Do not paste it into tickets, logs, source files, URLs, or shell command arguments. The API cannot recover the raw value from its digest.

Responses include `400` for invalid input, `401` without a valid JWT, `403` when the JWT is not backed by a current active Admin, and `409` when the normalized email already exists.

### Activate the pending Technician

`POST /api/auth/maintenance-technicians/activate`

This endpoint is anonymous because possession of the high-entropy, short-lived setup token is the activation credential.

Request:

```json
{
  "setupToken": "returned-once-secret",
  "password": "policy-valid-password",
  "passwordConfirmation": "policy-valid-password"
}
```

Success: `204 No Content`. The Technician can then use the existing `POST /api/auth/login` endpoint. Invalid, expired, or already consumed tokens receive the same safe `400` response. Rate-limited requests receive `429`.

## Local integration steps

From the repository root:

1. Apply the new migration to the intended local Development database:

   ```powershell
   dotnet ef database update --project backend/RentFlow.Api --startup-project backend/RentFlow.Api
   ```

2. Start the API normally:

   ```powershell
   dotnet run --project backend/RentFlow.Api
   ```

3. Sign in as the previously bootstrapped Admin through `POST /api/auth/login`. Keep the returned JWT only in a temporary process variable or an API client with secret masking.

4. Call `POST /api/admin/maintenance-technicians` with the three profile fields above. Copy the returned setup token directly into an approved secure channel; do not log or persist it.

5. Have the Technician call `POST /api/auth/maintenance-technicians/activate` before `passwordSetupExpiresAt`, entering the token and a password that satisfies the existing policy.

6. Verify the Technician can sign in through `POST /api/auth/login` and receives the existing `MaintenanceTechnician` role contract.

There is intentionally no public resend, token lookup, password-reset, or recovery endpoint in this stage. If a token expires before use, an authorized database operator must remove the unused pending local Technician and its token before an Admin provisions it again. Do not delete an active account for this purpose.

## Test configuration

The in-memory endpoint tests always run. PostgreSQL-specific migration tests use the existing isolated-test convention and require `RENTFLOW_TEST_POSTGRES_CONNECTION_STRING` to point to a disposable database whose name begins with `rentflow_component3_test`. Tests create and drop their own schemas and must never target the local development database.
