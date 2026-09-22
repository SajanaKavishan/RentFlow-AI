# React + Vite

## Tenant dashboard

The tenant dashboard reuses the shared role navigation, authenticated user profile,
API client and UI tokens. Its olive sidebar and cream card layout adapt to a mobile
navigation drawer and stacked cards on narrow screens.

- Application totals, under-review counts and change requests use
  `GET /api/rental-applications`.
- Upcoming viewings are approved records with a future `requestedDateTime` from
  `GET /api/viewings`; pending requests are counted separately. Dates display in
  the browser's local time zone. Summaries load when the dashboard mounts and
  failed requests can be retried independently.
- Both APIs derive the tenant from the bearer session. Loading, empty and failed
  responses have separate states; account changes discard previous summaries.
- Tenant My Viewings at `/modules/my-viewings` is a functional, read-only React
  page that displays real viewing records and statuses. Viewing booking and
  cancellation remain in the Flutter mobile app. Tenant My Applications web
  integration at `/modules/my-applications` remains pending.
- Property browsing/recommendations, lease/payments and maintenance await their
  owning modules. The dashboard shows pending states without invented records.

Run `npm run lint`, `npm test` and `npm run build` to validate the web app
(`npm.cmd` can be used on Windows if PowerShell script execution is disabled).

## Landlord dashboard

`/dashboard` renders the landlord overview for the authenticated Landlord role.
It reuses `usePropertyContext`: the dashboard accepts an actual selected property
via `?propertyId=<UUID>` or router navigation state `{ propertyId }`. No property
is hardcoded, selected automatically, or persisted in a separate store.

- Summaries call the existing `getViewingsByProperty` and
  `getApplicationsByProperty` services: `GET /api/viewings/property/{propertyId}`
  and `GET /api/rental-applications/property/{propertyId}`. The shared API client
  supplies the session token; backend property-ownership checks remain authoritative.
- Cards show total records and the same status counts used by the existing
  workflows: pending viewings, submitted applications, under-review applications
  and changes requested. No landlord-wide endpoints are used.
- Each card has independent loading, empty, error and retry states. Missing or
  invalid property context makes no requests and shows the shared selection state.
  Property/account changes clear previous summaries and ignore late responses.
- Shortcuts retain `/viewing-requests`, `/rental-applications` and `/ai-review`,
  forwarding the selected property in the query string. AI Review continues to
  use the existing application validation/document workflow.
- Needs Attention includes pending viewings, submitted/under-review applications,
  and confirmed AI workflows awaiting human review or reporting failure. AI
  summaries use `GET /api/rental-applications/{applicationId}/validation-runs`
  only for reviewable applications from the authorized property response, with
  at most four requests in flight. The newest run determines the workflow state;
  this dashboard never starts validation or makes a rental decision.
- AI Review remains accessible when summaries fail. Incomplete AI results are
  labeled explicitly; unavailable counts are never presented as zero. There is
  no aggregate AI summary endpoint, so request volume grows with the property's
  reviewable applications. The backend checks application ownership on each call.
- Recent Applications shows up to five real references, submitted/created dates
  and statuses from the property list. It omits tenant financial and document
  details and links to the existing authorized application detail workflow.
- Without valid property context, one selection notice appears and the workflow
  shortcuts remain available. Compact cards, attention rows, recent applications
  and shared sidebar branding adapt to narrower screens.
- Property integration still needs to provide a property-selection entry point
  into this dashboard. Property names, portfolio totals, pricing, leases, payments
  and maintenance remain with their owning modules; no new management module or
  property picker is introduced here.

## Authentication

Phase 2 stores only the JWT access token behind `tokenStorage` using browser
`sessionStorage`. The shared API client adds the bearer header and centrally
clears invalid sessions on 401 responses. The user profile is always restored
from `/api/auth/me`; decoded JWT data is not treated as profile truth.

This university-project strategy intentionally has no refresh token. A
production deployment may later adopt hardened HTTP-only cookie or token
handling appropriate to its threat model.

This template provides a minimal setup to get React working in Vite with HMR and some ESLint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)

## React Compiler

The React Compiler is not enabled on this template because of its impact on dev & build performances. To add it, see [this documentation](https://react.dev/learn/react-compiler/installation).

## Expanding the ESLint configuration

If you are developing a production application, we recommend using TypeScript with type-aware lint rules enabled. Check out the [TS template](https://github.com/vitejs/vite/tree/main/packages/create-vite/template-react-ts) for information on how to integrate TypeScript and [`typescript-eslint`](https://typescript-eslint.io) in your project.
