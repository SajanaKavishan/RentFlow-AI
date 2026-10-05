# Landlord viewing availability UX refactor

Implemented on the existing `feature/mobile-ui-redesign` branch. No branch operation, commit, push, or PR. This change affects React UI/navigation and documentation only.

## 1. Routes

Confirmed the existing canonical property workflow routes before implementation:

| Page | Route |
| --- | --- |
| Landlord Property Details | `/properties/:propertyId` |
| Edit Property | `/properties/:propertyId/edit` |
| Viewing Requests for a property | `/properties/:propertyId/viewing-requests` |
| Rental Applications for a property | `/properties/:propertyId/rental-applications` |
| New Viewing Availability settings | `/properties/:propertyId/viewing-availability` |

The new route follows the existing `/properties/:propertyId/...` convention. No route aliases were added. Existing unscoped request/application selection routes remain available.

## 2. Property Details header cleanup

The redundant `RentFlow AI` text was the shared shell's fallback title. It is now omitted only on landlord Property Details. The sidebar brand, mobile navigation, notification control, profile menu, session controls, and tenant/public shell behavior are preserved. Add Property is excluded from this title suppression. The property content starts with its existing Back to properties link.

## 3. Landlord Tools

The existing Manage this property card retains Viewing Requests, Rental Applications, Edit, Mark available/unavailable, and Delete. Its first-class Viewing availability action now opens the dedicated settings route for that property's actual ID, replacing the Edit Property hash link. It remains owner-only.

## 4. Dedicated settings page and editor

The page shows Viewing availability, the approval reminder, a compact property title/location card, and Back to property. The existing API-backed editor is reused as Schedule settings, with the stored timezone, supported slot durations, and all seven weekday controls in Monday-first display order.

Unconfigured schedules remain disabled and blank; enabling a weekday never inserts invented hours. Existing validation rules are reused. Invalid or unchanged drafts disable Save viewing availability; pending saves disable controls. The authoritative PUT response replaces the saved state only after success. Errors preserve the draft and allow retry. Unsaved edits retain navigation/refresh warnings.

The design uses existing olive/cream tokens, white bordered cards, restrained shadows, and aligned weekday rows. Small screens stack controls, including time inputs at 420px and below to avoid clipping browser-native time fields.

## 5. Add/Edit Property

The full weekday editor and schedule-dirty coupling were removed from the listing form. Edit Property has a small Viewing availability information card linking to the same dedicated page. Add Property has no schedule editor or schedule link before a real property exists. Listing validation and existing unsaved listing warnings remain intact.

## 6. Viewing Requests

A secondary Manage viewing availability link appears only for a verified selected property and points to that property's settings. Unscoped selection/error screens do not invent a property. Request review, approval, and rejection behavior is unchanged.

## 7. Property scope and authorization

The settings page requires an explicit valid property UUID. Landlords must load the authenticated owned portfolio and match both property ID and landlord ID before the editor mounts. No default or random property is selected. Missing, malformed, inaccessible, and failed property loads show safe error states.

Tenant and technician roles are blocked by ProtectedRoute. Existing backend Admin support is retained through an Admin-accessible route and the same protected availability APIs. Backend GET/PUT authorization remains authoritative, and denied schedule loads expose no editable controls. Requests and component state are keyed by user, role, property, and load attempt; late responses cannot overwrite another property's settings.

Persistence remains exclusively:

- GET `/api/properties/{propertyId}/viewing-availability`
- PUT `/api/properties/{propertyId}/viewing-availability`

No backend, migration, Flutter, slot-generation, timezone, duration, overlap, conflict, concurrency, request-blocking, or AvailableFrom semantics changed. No duplicate schedule store or landlord-global schedule was introduced.

## 8. Files changed

All code paths below are relative to `web/rentflow-web/src/`:

- `App.jsx`
- `shared/layout/AppShell.jsx`
- `features/properties/pages/ViewingAvailabilityPage.jsx` (new)
- `features/properties/pages/ViewingAvailabilityPage.test.jsx` (new)
- `features/properties/components/ViewingAvailabilityEditor.jsx`
- `features/properties/components/ViewingAvailabilityEditor.test.jsx`
- `features/properties/components/viewing-availability.css`
- `features/properties/pages/PropertyDetailsPage.jsx`
- `features/properties/pages/PropertyDetailsPage.test.jsx`
- `features/properties/pages/PropertyFormPage.jsx`
- `features/properties/pages/PropertyFormPage.test.jsx`
- `features/viewings/pages/ViewingRequestsPage.jsx`
- `features/viewings/pages/ViewingRequestsPage.test.jsx`
- `shared/property/PropertyWorkflowIntegration.test.jsx`

Documentation: `docs/landlord-viewing-availability-ux.md`.

## 9. ESLint

`npm run lint`: passed with no errors or warnings.

## 10. Tests and responsive checks

Focused React tests: **86 passed across 6 files** (availability page/editor, property details/form, viewing requests, and property workflow integration).

Full `npm test`: **479 passed across 50 files**.

Coverage includes schedule/context loading, real existing values, unconfigured states, weekday toggles, start/end/duration edits, pending save state, authoritative success, failure/retry with draft preservation, invalid/missing IDs, foreign ownership, backend access errors, Admin support, tenant/technician route denial, stale response isolation, unsaved navigation protection, all three management entry points, and landlord-only header cleanup.

Headless Chrome with isolated local API fixtures checked widths **320, 390, 600, 768, 1024, and 1440px**. No horizontal overflow; weekday/time/duration/save controls measured at least 44px high. Desktop and narrow-screen screenshots were visually reviewed. Fixtures were used only in the isolated browser; no live schedule was changed. Temporary screenshots and layout metrics are under `.tmp/availability-*`.

## 11. Build and diff validation

`npm run build`: passed. Vite retained its existing advisory about a bundle larger than 500kB.

`git diff --check`: passed (exit 0). Repository-wide checks emit permission warnings for pre-existing unrelated `agent/.pytest_tmp_asus` entries; those entries were not modified. The scoped web/documentation diff check is clean.
