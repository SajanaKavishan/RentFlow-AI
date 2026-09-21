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
- My Viewings and My Applications retain `/modules/my-viewings` and
  `/modules/my-applications`. These existing web destinations are integration
  placeholders; their management workflows are currently in the mobile app.
- Property browsing/recommendations, lease/payments and maintenance await their
  owning modules. The dashboard shows pending states without invented records.

Run `npm run lint`, `npm test` and `npm run build` to validate the web app
(`npm.cmd` can be used on Windows if PowerShell script execution is disabled).

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
