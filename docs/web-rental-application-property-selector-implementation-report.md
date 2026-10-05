# Rental Applications property selector implementation

1. **Exact application statuses and classification.** The existing backend `RentalApplicationStatus` enum and web `RENTAL_APPLICATION_STATUS` agree:

   | Value | Status | Attention category |
   | --- | --- | --- |
   | 0 | Draft | Tenant prepares/submits; no immediate landlord action |
   | 1 | Submitted | Landlord action / review required |
   | 2 | UnderReview | Landlord action / review required |
   | 3 | ChangesRequested | Waiting on tenant changes and resubmission |
   | 4 | Approved | Application decision final; excluded from review attention |
   | 5 | Rejected | Final; excluded |
   | 6 | Withdrawn | Final; excluded |

   This classification concerns application review. It does not imply that an approved application's later offer or lease workflow has no further work. Existing service transitions allow the tenant to edit Draft/ChangesRequested, resubmit into Submitted, and the landlord to review/decide Submitted/UnderReview. Those rules were not changed.

2. **Action-required semantics.** Count only Submitted (1) and UnderReview (2), matching the existing selected-workspace `Awaiting review` counter and sidebar logic. The compact badge reads `2 to review`, with `2 applications need your attention` underneath. Draft, ChangesRequested, Approved, Rejected, and Withdrawn do not contribute. There is no invented generic Pending application status.

3. **Existing architecture.** `RentalApplicationsPage` reads property scope through `usePropertyContext`, verifies it against `OwnedPropertiesProvider`'s authenticated `/api/properties/mine` collection, and loads the existing property application list only after selection. The same page serves AI Review routes. Application details, documents, validation findings, and landlord actions remain in the existing components. The initial Rental Applications screen previously used the shared plain-link property selector.

4. **Endpoint decision and implementation.** No landlord-wide application list or count summary existed. `/api/rental-applications` and `/eligible-properties` are Tenant-only; the landlord list is property-scoped. Added `GET /api/rental-applications/mine/action-counts`, authorized only for Landlord. JWT identity supplies the owner; a caller-supplied `landlordId` has no authority. One EF query joins applications to currently owned properties, filters Submitted/UnderReview, groups by PropertyId, and returns only `propertyId` and `actionRequiredCount`. No tenant information is loaded into the response. Existing endpoints and authorization were not changed. No schema migration or dependency was needed. Optional total counts were omitted to keep the response focused.

5. **Card layout.** Rental Applications now uses the same white horizontal property cards as Viewing Requests, on the existing cream page. Cards have subtle neutral borders/shadows, 16px corners, olive accents, pale olive hover/active states, a left thumbnail, title/address, a compact upper badge, and review metadata. Zero-count cards remain fully enabled.

6. **Image source and fallback.** The shared card retains Viewing Requests' existing `getPropertyImages` and `getPropertyImageUrl` flow: primary image, otherwise the first returned record from the existing ordered image list. Only the chosen URL is resolved. Images use lazy loading and cover cropping. Missing photos, image-service failures, unusable URL responses, and image-load errors use the existing decorative building icon. There are no fabricated production photos, URLs, or counts. Tests and temporary browser checks use fixtures only.

7. **Badge and zero behavior.** Positive counts show a pale olive `N to review` badge and explicit attention text, with singular/plural wording. A known zero has no attention badge and says `No applications need your attention`. Missing summary rows become zero only after a successful validated response. Loading, failure, and malformed responses never masquerade as zero.

8. **Sidebar decision.** Audit found an existing property-scoped Rental Applications badge, using Submitted/UnderReview and property-aware dismissal/publication logic. It is not a reliable portfolio-wide global count. That behavior is preserved; no new global badge was introduced. Property-card summaries do not publish an aggregate into the sidebar. Existing shell navigation/badge tests pass.

9. **Selection and refresh.** The whole native button card navigates to the exact `/properties/{propertyId}/rental-applications` workspace. Click, Enter, Space, browser back, and `Change property` are covered. The original `Back to Property` link is retained. Selected application loading, search/filtering, details, document review, AI validation links/findings, actions, and lifecycle remain unchanged. On the initial Rental Applications selector, the existing Refresh button now reloads the single summary; it does not load an application list for every property or refetch thumbnails. In the selected workspace it retains its existing scoped-list refresh. Returning to the selector reloads the summary. The separate AI Review selector and routes retain their previous behavior.

10. **Loading and errors.** Both workspaces share a two-card decorative skeleton for owned-property loading, alongside the established loading heading. Count loading displays a small notice and unknown-count labels while leaving cards usable. Count failures display a neutral unavailable notice and `Retry counts`; invalid, duplicate, or negative count rows take that same failure path. Existing owned-property error/retry and no-properties states remain truthful and do not fetch summary counts or images. Late responses from superseded requests are ignored.

11. **Responsive and accessible behavior.** The shared grid uses two columns above 1200px and one below. Thumbnails are 120px, or 110px at narrow widths; titles are 18px/17px, addresses 14px/13px, and badges wrap safely. Native buttons support Tab, Enter, Space, and visible focus. Accessible labels state the property name and actual review count, or that the count is unavailable. Real images have meaningful property alt text; fallback and directional icons are decorative. Temporary headless Chrome checks confirmed two columns at 1440px and one at 1024/390/360/320px, with no internal card overflow. Desktop and 390px screenshots were inspected. At 320px with classic desktop scrollbars, the pre-existing app-wide minimum width still causes slight page overflow; the cards fit their container.

12. **Shared reuse with Viewing Requests.** Extracted `LandlordWorkspacePropertyCard`, its real-image handling, common CSS, owned-property loading skeleton, and `usePropertyCountSummary`. Viewing Requests now consumes these shared pieces while retaining its Pending-only semantics, wording, route selection, and count retry behavior. Rental Applications supplies its own action-count field and review wording. Domain wording is not embedded into the shared card. Viewing Requests regression tests passed.

13. **Files changed.**

    - `backend/RentFlow.Api/Controllers/RentalApplicationsController.cs`
    - `backend/RentFlow.Api/DTOs/RentalApplications/PropertyApplicationActionCountDto.cs`
    - `backend/RentFlow.Api/Services/Interfaces/IRentalApplicationService.cs`
    - `backend/RentFlow.Api/Services/RentalApplicationService.cs`
    - `backend/RentFlow.Api.Tests/Authentication/RentalApplicationActionCountsEndpointsTests.cs`
    - `web/rentflow-web/src/features/rentalApplications/components/ApplicationPropertySelector.jsx`
    - `web/rentflow-web/src/features/rentalApplications/components/ApplicationPropertySelector.test.jsx`
    - `web/rentflow-web/src/features/rentalApplications/pages/RentalApplicationsPage.jsx`
    - `web/rentflow-web/src/features/rentalApplications/pages/RentalApplicationsPage.test.jsx`
    - `web/rentflow-web/src/features/rentalApplications/services/rentalApplicationApiService.js`
    - `web/rentflow-web/src/features/viewings/components/ViewingPropertySelector.jsx`
    - `web/rentflow-web/src/features/viewings/components/ViewingPropertySelector.test.jsx`
    - `web/rentflow-web/src/features/viewings/components/viewing-property-selector.css`
    - `web/rentflow-web/src/shared/property/LandlordWorkspacePropertyCard.jsx`
    - `web/rentflow-web/src/shared/property/landlord-workspace-property-selector.css`
    - `web/rentflow-web/src/shared/property/usePropertyCountSummary.js`
    - `web/rentflow-web/src/shared/property/PropertyWorkflowIntegration.test.jsx`
    - This report.

14. **Web validation.** Focused Rental Applications page/selector, Viewing Requests selector, shell/sidebar, and property integration tests: **95 passed across 5 files**. Full web suite: **593 passed across 55 files**. `npm run lint` passed. `npm run build` passed with the existing Vite warning for the main bundle exceeding 500kB. Coverage includes owned-property grouping/display, positive/zero counts, primary/first/fallback images, keyboard selection, unknown/error/malformed counts, property loading/error/empty states, exact selection, browser navigation, return-summary refresh, and one summary call per Refresh without application-list fan-out or image refetch. Existing document, AI validation, action, search/filter, and navigation tests passed in the full suite.

15. **Backend validation.** New endpoint authorization/count tests: **13 passed**. Each of the seven lifecycle statuses has an explicit count inclusion/exclusion case. Further coverage verifies grouping, multiple properties, other landlords, zero-action/empty portfolios, orphan applications, JWT authority despite a caller landlordId query parameter, a tenant-free response schema, 403 for Tenant/Admin/MaintenanceTechnician, and 401 for anonymous access. Full backend suite: **988 passed, 16 skipped**, no failures. Skips require the PostgreSQL integration environment. Tests used a temporary .NET artifacts directory to avoid the running local API's normal build output. Restore emitted a NuGet vulnerability-feed availability warning, but compilation and tests succeeded.

16. **Diff and branch checks.** `git diff --check` passed, and newly created files were also checked for whitespace errors. Work stayed on `feature/full-app-polish`, with no branch operations, commit, push, or PR. Pre-existing inaccessible pytest temporary artifacts were preserved.

17. **Remaining limitations.** Summary counts are snapshots refreshed on entry, Refresh, or retry; no polling was added. Image metadata and signed URLs still use the existing per-property image APIs, while review counts use one summary request. Production storage and a live landlord session were not used for browser checks. PostgreSQL integration tests require an external test environment. The existing app-wide 320px minimum-width behavior and main-bundle size warning remain outside this selector change.
