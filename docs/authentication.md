# Shared authentication and role authorization

ASP.NET Core is RentFlow's authentication and authorization authority. The React web app and Flutter mobile app use the same `/api/auth` endpoints, PostgreSQL `Users` table, JWT format, and roles. The Python agent service does not authenticate end users directly.

Client-side role checks are for navigation and presentation only. Every protected backend operation must enforce authorization in ASP.NET Core.

## Roles

The controlled `UserRole` values are:

- `Tenant`
- `Landlord`
- `MaintenanceTechnician`
- `Admin`

Public registration accepts only `Tenant` and `Landlord`. A caller cannot self-register as `Admin` or `MaintenanceTechnician`; those roles require a future authorized administrative workflow or controlled development seed.

## Configuration

The committed `appsettings.json` contains the JWT issuer, audience, expiry, and an intentionally empty signing-key setting. Configure a secret of at least 32 bytes locally without adding it to source control:

```powershell
cd backend/RentFlow.Api
dotnet user-secrets set "Jwt:SigningKey" "use-a-long-random-development-secret-here"
```

Deployment environments should set `Jwt__SigningKey` through their secret manager. The API validates JWT configuration at startup. Default access-token lifetime is 30 minutes; Phase 1 does not issue refresh tokens.

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

## JWT claims

Access tokens include:

- `sub`: application user ID (`Guid`)
- `role`: one allow-listed role string
- `email`: the user's safe email identity context for clients
- `jti`: unique token ID

Tokens are signed with HMAC SHA-256 and validated for signature, issuer, audience, and lifetime. The signing key is not included in any response or log.

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
