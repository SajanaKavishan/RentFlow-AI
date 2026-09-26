# Shared authentication and role authorization

ASP.NET Core is RentFlow's authentication and authorization authority. The React web app and Flutter mobile app use the same `/api/auth` endpoints, PostgreSQL `Users` table, JWT format, and roles. The Python agent service does not authenticate end users directly.

Client-side role checks are for navigation and presentation only. Every protected backend operation must enforce authorization in ASP.NET Core.

## Roles

The controlled `UserRole` values are:

- `Tenant`
- `Landlord`
- `MaintenanceTechnician`
- `Admin`

Public registration accepts only `Tenant` and `Landlord`. A caller cannot self-register as `Admin` or `MaintenanceTechnician`. The initial Admin is created through the controlled bootstrap command, and active Admins can provision inactive Maintenance Technician accounts through the documented staff-provisioning workflow.

## Configuration

The committed `appsettings.json` contains the JWT issuer, audience, expiry, and an intentionally empty signing-key setting. Configure a secret of at least 32 bytes locally without adding it to source control:

```powershell
cd backend/RentFlow.Api
dotnet user-secrets set "Jwt:SigningKey" "use-a-long-random-development-secret-here"
```

Deployment environments should set `Jwt__SigningKey` through their secret manager. The API validates JWT configuration at startup. Default access-token lifetime is 30 minutes. The application does not issue refresh tokens; a successful password change returns a replacement access token.

Password-reset tokens expire after 45 minutes by default. Configure the lifetime with `PasswordReset__TokenLifetimeMinutes` (30-60 minutes). `PasswordReset__DevelopmentWebBaseUrl` controls only the local Development reset-link origin and defaults to `http://localhost:5173`.

Non-Development deployments send password-reset links through SMTP and require all of these environment variables:

- `Email__SmtpHost`
- `Email__SmtpPort`
- `Email__Username`
- `Email__Password`
- `Email__FromAddress`
- `Email__FromName`
- `Email__UseSsl`
- `Frontend__BaseUrl`

`Frontend__BaseUrl` must be an absolute HTTP or HTTPS origin/base path without a query or fragment. When `Email__UseSsl` is `true`, port 465 uses implicit TLS and other ports require STARTTLS. When it is `false`, the connection is unencrypted and should be used only for an explicitly trusted SMTP relay. Non-Development configuration is validated when the API starts.

Example PowerShell setup (placeholder values only):

```powershell
$env:Email__SmtpHost = "<smtp-host>"
$env:Email__SmtpPort = "587"
$env:Email__Username = "<smtp-username>"
$env:Email__Password = "<smtp-password-from-secret-manager>"
$env:Email__FromAddress = "<verified-sender-address>"
$env:Email__FromName = "RentFlow AI"
$env:Email__UseSsl = "true"
$env:Frontend__BaseUrl = "https://<rentflow-web-host>"
```

Never commit SMTP credentials, provider app passwords, API keys, or personal email passwords. Supply secrets through the deployment platform's secret manager (or .NET user-secrets for local non-Development testing), and restrict the SMTP credential to the approved sender where the provider supports it.

In Development, the API does not contact SMTP and returns `developmentResetLink` for local testing. Eligible accounts receive a usable link; other valid requests receive the same field with an opaque non-usable link to preserve response uniformity. Outside Development, eligible accounts are emailed at their stored address and `developmentResetLink` is always absent. SMTP failures are recorded as a safe server-side error without the recipient, token, reset URL, credentials, or provider message; the anonymous caller still receives the generic success response.

## Endpoints

### `POST /api/auth/register`

Public. Request:

```json
{
  "fullName": "Jamie Silva",
  "email": "jamie@example.com",
  "phoneNumber": "+94770000000",
  "password": "Example1!Password",
  "role": "Tenant"
}
```

Returns HTTP 201 with `accessToken`, `expiresAt`, and a safe `user` profile. Passwords must be 8-128 characters and contain upper- and lowercase letters, a number, and a non-alphanumeric character. Email matching is trim- and case-insensitive. The password hash is never returned.

### `POST /api/auth/login`

Public. Accepts `email` and `password`. A successful request returns the same safe auth response as registration. Wrong passwords, unknown emails, and inactive accounts all receive HTTP 401 with the generic `Invalid email or password.` detail.

### `GET /api/auth/me`

Requires `Authorization: Bearer <accessToken>`. The user is identified from the signed JWT `sub` claim; this endpoint never accepts a user ID in the route or query string. It returns `id`, `fullName`, `email`, `phoneNumber`, and `role` for the active user.

### `PUT /api/auth/change-password`

Requires authentication. Accepts `currentPassword`, `newPassword`, and `newPasswordConfirmation`; it never accepts a user ID or role. A successful change updates the password hash, increments the user's token version, creates the mandatory `account.password_changed` notification, and returns `message`, a replacement `accessToken`, and `expiresAt`. Every token issued before the change is rejected on its next authenticated request, including tokens from other sessions.

### `POST /api/auth/forgot-password`

Public and rate-limited by client IP. Accepts `email`. Every validly formatted request returns HTTP 200 with the generic message `If an account matches that email, password reset instructions will be sent.` regardless of account existence, activation state, role, or SMTP delivery outcome. Eligible accounts receive a cryptographically random 256-bit reset token; only its SHA-256 digest is stored. Issuing a new token consumes prior outstanding tokens for that account.

In Development only, the response also contains `developmentResetLink` for local testing. Existing eligible accounts receive a usable link; all other valid requests receive the same field and an opaque non-usable link to avoid enumeration through the forgot-password response. Non-Development responses omit this field completely and send `/reset-password#token=<raw-token>` using the configured `Frontend__BaseUrl`. The email states that the link expires after the configured token lifetime (45 minutes by default) and can be ignored when the recipient did not request it.

### `POST /api/auth/reset-password`

Public and separately rate-limited by client IP. Accepts `token`, `newPassword`, and `newPasswordConfirmation`. The token must exist, be unexpired, unconsumed, and belong to an active account with an established password. The password uses the existing password policy and must match its confirmation.

A successful reset atomically replaces the password hash, increments `TokenVersion`, consumes all outstanding reset tokens for the account, and creates exactly one mandatory `account.password_reset` notification titled `Password reset`. It returns only `Your password was reset successfully.` and does not create a login session or access token. Invalid, expired, and reused tokens share the same safe HTTP 400 response.

### Profile endpoints

- `PUT /api/auth/profile` updates the authenticated user's name and phone number.
- `POST /api/auth/profile-image` uploads a validated JPEG, PNG, or WEBP image of at most 5 MB.
- `GET /api/auth/profile-image` returns only the authenticated user's image with private, no-store caching.

All ownership comes from the validated JWT subject.

### Notification preferences

`GET` and `PUT /api/notification-preferences` operate only on the authenticated user. Viewing and rental-application preferences suppress only optional events created after the preference is disabled; existing notifications remain stored. Account and security notifications are mandatory, cannot be disabled by the client or API, and bypass optional delivery preferences.

### Support requests

Authenticated users create tickets with `POST /api/support-tickets` and retrieve only their own tickets with `GET /api/support-tickets/mine`. Ticket ownership is derived from the JWT and is never accepted from the request body.

The Admin queue under `/api/admin/support-tickets` uses the `ActiveAdmin` policy. Admins may list and filter tickets, view details, and perform only the forward status transitions `Open -> InProgress`, `Open -> Resolved`, and `InProgress -> Resolved`. Admin responses expose only the ticket fields and limited requester identity required by the management UI.

## JWT claims

Access tokens include:

- `sub`: application user ID (`Guid`)
- `role`: one allow-listed role string
- `email`: the user's safe email identity context for clients
- `token_version`: the user's current session-generation number
- `jti`: unique token ID

Tokens are signed with HMAC SHA-256 and validated for signature, issuer, audience, and lifetime. Token validation also loads the current user and rejects deleted or inactive accounts, stored-role mismatches, and stale token versions. The signing key is not included in any response or log.

## Using authorization in backend components

Require any authenticated user with `[Authorize]`. Apply a role boundary with the shared enum name so it stays refactor-safe:

```csharp
[Authorize(Roles = nameof(UserRole.Landlord))]
```

For multiple roles, use an authorization policy or a comma-separated `Roles` restriction rather than relying on UI checks. Controllers that need the caller's identity inject `ICurrentUserService`, which exposes `IsAuthenticated`, `UserId`, and `Role`; raw `HttpContext` claim parsing is not repeated across controllers.

Phase 3A migrated Viewing, Rental Application, Application Document, and Application Validation endpoints from caller-supplied tenant identity to JWT identity:

```text
Before: client -> ?tenantId=<guid>
After:  client -> Authorization: Bearer <JWT>
        ASP.NET Core -> ICurrentUserService.UserId -> TenantId
```

Unknown query parameters are ignored, so a legacy or malicious `tenantId` query value cannot change the authenticated tenant. Missing, empty, or malformed JWT `sub` or `role` claims fail token validation. Tenant resource lookups include `TenantId` in the database predicate and return 404 for another tenant's private resource.

## Phase 3A role matrix

| Capability | Tenant | Landlord | Admin | MaintenanceTechnician |
| --- | --- | --- | --- | --- |
| Create/list/get/cancel viewing | Own resources only | Review reads | Review reads | Denied |
| Approve/reject viewing | Denied | Allowed* | Allowed | Denied |
| Create/list/get/update/submit/withdraw application | Own resources only | Review reads | Review reads | Denied |
| Review/approve/reject/request changes | Denied | Allowed* | Allowed | Denied |
| Upload/delete application documents | Own eligible application only | Denied | Denied | Denied |
| List/get/download application documents | Own application only | Review workflow* | Review workflow | Denied |
| Run/view validation workflows | Denied | Allowed* | Allowed | Denied |

`*` Landlord-to-specific-property ownership is not available in this component. Phase 3A enforces the Landlord/Admin role boundary and preserves existing property/application relationships. Cross-component integration must add property ownership/management authorization before production release; it must not be inferred or duplicated here.

## Phase 3A tenant API contract

Every endpoint below requires a bearer token. The following obsolete tenant identity parameters were removed:

- `POST /api/viewings?tenantId=...` is now `POST /api/viewings`.
- `GET /api/viewings/tenant/{tenantId}` is now `GET /api/viewings`.
- `PATCH /api/viewings/{id}/cancel?tenantId=...` is now `PATCH /api/viewings/{id}/cancel`.
- `POST /api/rental-applications?tenantId=...` is now `POST /api/rental-applications`.
- `GET /api/rental-applications/tenant/{tenantId}` is now `GET /api/rental-applications`.
- `PUT /api/rental-applications/{id}?tenantId=...` is now `PUT /api/rental-applications/{id}`.
- Application `submit` and `withdraw` routes no longer accept `tenantId`.
- Document upload/list/get/download/delete routes no longer accept `tenantId`.

Real resource identifiers such as `id`, `applicationId`, `documentId`, and `propertyId` remain unchanged. DTO response shapes are unchanged, and `ApplicationDocumentResponseDto` does not expose `StorageKey` or bucket details.

The existing `TenantId` columns remain without a new foreign key migration. Adding referential integrity to `Users.Id` is a future schema-hardening task and should be coordinated against existing data.
