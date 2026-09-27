# RentFlow AI web application

The React web app provides a shared authenticated shell for Tenant, Landlord,
Maintenance Technician and Admin accounts. The shell includes role-scoped
navigation, an unread-notification indicator, Profile, logout, responsive mobile
navigation and consistent olive/cream UI tokens.

Client-side guards keep role workspaces separate, while the ASP.NET Core API
remains authoritative for resource authorization. Unavailable business modules
are shown as explicit integration-pending states and do not invent records,
counts, actions or endpoints.

## Role workspace status

| Role | Completed web UI | Outstanding integrations |
| --- | --- | --- |
| Tenant | Dashboard, My Viewings, My Applications, Notifications and Profile | Property discovery, lease/payments and maintenance |
| Landlord | Property-scoped Dashboard, Viewing Requests, Rental Applications, AI Review, Notifications and Profile | Property selection/management, pricing/lease, payments and maintenance |
| Maintenance Technician | Dedicated Dashboard, Assigned Work workspace, Notifications and Profile | Authenticated "my assigned work" collection and its Maintenance-owned workflow |
| Admin | Dedicated Dashboard, Users workspace, AI & System Overview workspace, Notifications and Profile | Admin user directory/management contract and system-wide AI/reporting/status aggregate |

## Tenant workspace

The Tenant dashboard loads real account-scoped summaries from
`GET /api/rental-applications` and `GET /api/viewings`. Upcoming viewings include
only approved future records; pending viewing requests are reported separately.
Each real request has loading, empty, error and retry behavior, and changing the
authenticated account clears previous summary state.

- `/modules/my-viewings` is a functional read-only page for the Tenant's real
  viewing requests and landlord responses. Booking and cancellation remain in
  the Flutter app.
- `/modules/my-applications` is a functional read-only page for real application
  records, statuses and landlord feedback. It supports status filtering and links
  to the authorized application detail. Creating and updating applications remain
  in the Flutter app.
- `/modules/properties`, `/modules/lease-payments` and `/modules/maintenance`
  clearly identify their owning integrations as pending.

## Landlord workspace

The Landlord dashboard and workflows use `usePropertyContext`. A real selected
property can be supplied through `?propertyId=<UUID>`, supported property routes,
or router state `{ propertyId }`. No property is hardcoded or selected
automatically. Dashboard shortcuts, sidebar links and application detail links
preserve a valid selected property in their destination URLs.

- Viewing summaries and Viewing Requests use
  `GET /api/viewings/property/{propertyId}`.
- Application summaries, Rental Applications and AI Review use
  `GET /api/rental-applications/property/{propertyId}`.
- AI summary rows query
  `GET /api/rental-applications/{applicationId}/validation-runs` only for
  reviewable applications already returned by the authorized property response.
  The dashboard never starts validation or makes a rental decision.
- Missing or invalid property context makes no scoped API request and presents a
  property-selection state. API-backed sections expose loading, empty, error and
  retry states only when a real request exists.
- `/modules/properties`, `/modules/pricing-lease`, `/modules/payments` and
  `/modules/maintenance` remain explicit integration-pending destinations owned
  by their corresponding business modules.

There is no landlord-wide AI summary API. Validation request volume therefore
depends on the property's reviewable applications, and the backend checks access
for each application.

## Maintenance Technician workspace

The Technician has a dedicated dashboard and responsive Assigned Work page at
`/modules/assigned-work`. Both preserve access to Notifications, Profile and
logout. The current Maintenance API does not expose an authenticated collection
of work assigned to the signed-in Technician, so the page displays an
integration-pending state without maintenance records, counts or job actions.

Assigned-work details, estimates, start and completion controls must remain
unavailable until the Maintenance-owned API supplies the assignment collection,
record authorization and supported workflow contract.

## Admin workspace

The Admin has a dedicated dashboard and two guarded workspaces:

- `/modules/users` documents the pending Admin-authorized user directory. The
  existing `/api/auth/me` endpoint identifies only the signed-in account; it is
  not a user-list API. No user totals or account-changing controls are shown.
- `/modules/ai-system-overview` documents the pending Admin aggregate for
  system-wide AI activity, validation history, reporting and service status.
  Existing validation routes require a known application or workflow ID and are
  not combined to imitate an Admin overview. No AI scores, charts, health states,
  activity records or totals are shown.

Both pages retain Dashboard, Notifications, Profile and logout access and are
blocked for non-Admin roles.

## Shared account workflows

Notifications use the authenticated notification collection, unread-count and
mark-read APIs. Loading, empty, error and retry controls correspond to real
requests. Related-record navigation remains constrained by role and resource
authorization.

Profile displays authenticated account data for every role. Unsupported profile,
password, preference and support actions are visibly disabled. Tenant document
access uses the existing application-document APIs; logout clears the local
session and returns the user to sign-in.

## Authentication

The web app stores only the JWT access token through `tokenStorage` using browser
`sessionStorage`. The shared API client supplies the bearer header and clears an
invalid session on HTTP 401. The authenticated profile is restored from
`GET /api/auth/me`; decoded token data is not treated as profile truth.

Public registration remains limited to Tenant and Landlord. Technician and Admin
accounts require an authorized administrative workflow or controlled development
seed; the web UI does not provide public staff registration.

## Google Maps configuration

The Property Details page can show a Google Maps Embed preview for the real
property address and city. Copy `.env.example` to a local Vite environment file
and set `VITE_GOOGLE_MAPS_API_KEY`. Never commit the real browser key.

In Google Cloud, restrict this browser key to:

- the **Maps Embed API** only; and
- approved frontend **HTTP referrers/domains** only (including the exact local
  development origin when needed).

If the variable is unset or the property has no usable address/city, the page
keeps showing the textual location and an honest map-unavailable state.

## Validation commands

From `web/rentflow-web` run:

```powershell
npm.cmd run lint
npm.cmd run test
npm.cmd run build
```

Use the equivalent `npm` commands on environments where PowerShell script
execution is enabled.
