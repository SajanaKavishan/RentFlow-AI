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

For multiple roles, use a policy registered through `AddAuthorization` rather than relying on UI checks. Services that need the caller's identity should inject `ICurrentUserService`, which exposes `IsAuthenticated`, `UserId`, and `Role`; avoid parsing `HttpContext` throughout business services.

Existing Rental Application, Viewing, and Document endpoints intentionally keep their current `tenantId` parameters during Phase 1 so team workflows are not broken. Their future migration is:

```text
Current: ?tenantId=<guid>
Future:  authenticated user ID from the JWT sub claim
```

Phase 2 should protect each component endpoint, replace caller-supplied tenant identity with `ICurrentUserService.UserId`, verify resource ownership and landlord relationships, and then remove obsolete parameters. Applicant name and phone context should come through the authenticated user relationship rather than being duplicated into `RentalApplication` without a domain reason.
