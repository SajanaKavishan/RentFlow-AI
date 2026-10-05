# Web Viewing Requests property selector implementation

1. **Existing architecture.** `ViewingRequestsPage` resolves property scope from the route/query/state through `usePropertyContext`. `OwnedPropertiesProvider` loads authenticated `/api/properties/mine`, and `useOwnedPropertySelection` prevents opening properties outside that collection. The initial state previously used the shared text-link `PropertySelectionState`. The selected workspace uses the property viewing list, authorized approved-viewing details, and existing decision endpoints. Other workflows continue using the shared selector.

2. **Summary endpoint decision.** There was no landlord-wide viewing collection or per-property count summary. `/api/viewings` is Tenant-only; `/api/viewings/property/{propertyId}` requires one scoped request per property. Added only `GET /api/viewings/mine/pending-counts`. It requires the Landlord role and takes the landlord identity from the authenticated JWT, with no caller-supplied landlord authority. It returns only `propertyId` and `pendingCount`. Tenant, Admin, and MaintenanceTechnician callers receive 403; anonymous callers receive 401.

3. **Exact count computation.** One asynchronous EF query joins viewing requests to their currently owned properties, filters `ViewingStatus.Pending` (0), groups by `PropertyId`, and projects counts. Approved (1), Rejected (2), Cancelled (3), and Completed (4) are excluded. The browser loads this summary once when the selector mounts, rather than loading each property's viewing list. Missing summary rows map to zero only after a successful validated response.

4. **Card layout.** Added a Viewing Requests-specific selector with white horizontal cards on the existing cream page, subtle borders/shadows, 16px corners, olive accents, pale olive hover/active backgrounds, and a directional icon. Each card includes a thumbnail, 18px title, 14px address, and 12px request metadata. The existing selected workspace layout and actions remain intact.

5. **Real images and fallback.** Reuses `getPropertyImages` and `getPropertyImageUrl` and the existing storage-backed image endpoints. It chooses the primary image, otherwise the first returned image; the existing image service orders that list by sort order. Only the chosen image URL is resolved. The 120px thumbnail uses cover cropping and lazy image loading. Missing images, API failures, invalid URL responses, and image-load failures use the existing RentFlow building icon. No image URLs or counts are hardcoded in production code. Fixture URLs exist only in tests.

6. **Pending badges.** Positive counts display a compact pale olive `2 pending` badge and explicit attention text. Singular wording is handled. Color is supplementary to the visible count and label.

7. **Zero, loading, and errors.** A known zero shows `No pending viewing requests` without an attention badge. Count loading and count failures never render zero or the zero-state sentence. Cards remain usable, with a loading notice or a small unavailable notice and `Retry counts`. Malformed/duplicate/negative count responses are treated as failures. Owned-property loading, safe retryable errors, and truthful no-properties states reuse the established selection component; those states do not fetch counts or images.

8. **Selection and navigation.** The whole native button card opens `/properties/{exactPropertyId}/viewing-requests`. No intermediate screen was added. Browser back is preserved, and the selected view adds `Change property` while retaining `Back to Property`. Returning to the selector reloads the summary. Existing selected-property loading, Total/Pending counters, request search, status filters, details, approve/reject actions, refresh, and `Manage viewing availability` are preserved.

9. **Sidebar behavior.** `AppShell`, its pending-viewing context, navigation configuration, and badge/dismissal logic were not changed. Audit found that the existing sidebar viewing badge is property-scoped, rather than an aggregate across the landlord's portfolio. Card summaries remain independent and do not publish their aggregate into the sidebar. Existing sidebar ownership/status and dismissal tests pass.

10. **Responsive and accessibility behavior.** The grid has two columns above 1200px and one below; card widths follow their container. At narrow widths, thumbnails are 110px, titles 17px, addresses 13px, and badges wrap safely. Native buttons support Tab, Enter, and Space with a visible focus outline. Accessible names include the property title and known pending count, or state that the count is unavailable. Real images have property-specific alt text; fallback and arrow icons are decorative. A headless Chrome check with temporary API fixtures confirmed two columns at 1440px, one at 1024/390/320px, and no overflow inside any card. Desktop and 320px screenshots were inspected. The existing app-wide 320px minimum width causes slight page overflow at a 320px desktop viewport with classic scrollbars; the cards themselves fit their container.

11. **Files changed.**

    - `backend/RentFlow.Api/Controllers/ViewingsController.cs`
    - `backend/RentFlow.Api/DTOs/Viewings/PropertyPendingViewingCountDto.cs`
    - `backend/RentFlow.Api/Services/Interfaces/IViewingService.cs`
    - `backend/RentFlow.Api/Services/ViewingService.cs`
    - `backend/RentFlow.Api.Tests/Authentication/ViewingPendingCountsEndpointsTests.cs`
    - `web/rentflow-web/src/features/viewings/components/ViewingPropertySelector.jsx`
    - `web/rentflow-web/src/features/viewings/components/ViewingPropertySelector.test.jsx`
    - `web/rentflow-web/src/features/viewings/components/viewing-property-selector.css`
    - `web/rentflow-web/src/features/viewings/pages/ViewingRequestsPage.jsx`
    - `web/rentflow-web/src/features/viewings/pages/ViewingRequestsPage.test.jsx`
    - `web/rentflow-web/src/features/viewings/services/viewingApiService.js`
    - `web/rentflow-web/src/shared/property/PropertyWorkflowIntegration.test.jsx`
    - This report.

12. **Web validation.** Focused selector, Viewing Requests, shell/sidebar, and owned-property integration coverage: **77 passed**. Full web suite: **576 passed across 54 files**. `npm run lint` passed. `npm run build` passed, with Vite's existing warning about the main bundle exceeding 500kB. Coverage includes independent counts, zero badges, primary/first images, decorative and failed-image fallbacks, click/Enter/Space selection, navigation, property/count states and retries, malformed summaries, and refreshed counts after returning. Existing request action/search/filter and shell tests passed.

13. **Backend validation.** New endpoint tests: **6 passed**. Full backend suite: **975 passed, 16 skipped**, with no failures. Tests cover grouped Pending-only counts, multiple owned properties, other landlords, properties with no Pending requests, orphan requests, ignored caller landlord ID, empty portfolios, roles, anonymous access, and the exact tenant-free response schema. The skipped tests require the PostgreSQL integration environment. A running local API locked its normal executable, so tests were built and run through .NET's temporary `--artifacts-path`, without stopping that API. Restore emitted a NuGet vulnerability-feed availability warning; build and tests succeeded.

14. **Diff and branch checks.** `git diff --check` passed, and new files were checked separately for whitespace errors. Work remained on `feature/full-app-polish`. No branch operations, commits, pushes, or PRs were performed. Pre-existing inaccessible pytest temporary artifacts were left untouched.

15. **Limitations.** Counts are snapshots refreshed on selector entry or retry; there is no new live polling. Existing image metadata and signed-URL endpoints still require image requests per property; there are no per-property viewing requests for counts. Browser visual checks used temporary fixtures, not a production landlord session. Live PostgreSQL tests and production image storage were not available for end-to-end checks. The pre-existing app-wide minimum-width and bundle-size behavior described above remains outside this selector change.
