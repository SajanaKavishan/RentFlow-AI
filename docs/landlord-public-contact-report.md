# Landlord public contact implementation report

Completed on 2026-10-03 on the current branch. No branch operations, commit, push, or PR.

1. **Final model fields:** `ApplicationUser.PublicContactPhone` is an optional string, limited to 32 characters. `PublicContactEnabled` is a boolean with a database default of `false`. An enabled setting requires a usable public number. Supplied numbers are trimmed and validated with the existing viewing-contact formats: supported Sri Lankan/international punctuation, 7–15 digits, and at most 32 characters. Country formats are preserved.

2. **Migration:** `20261003110524_AddLandlordPublicContact` adds nullable `Users.PublicContactPhone` and non-null `Users.PublicContactEnabled DEFAULT FALSE`. Existing users receive null/false. The EF designer and snapshot are updated. Inspected SQL contains only the two column additions and migration-history insertion, with no phone backfill or fabricated data. The migration was generated and checked, not applied to an application database.

3. **Private account phone:** `PhoneNumber` remains a separate field. Neither migration, registration, owner UI, nor contact disclosure copies it into the public field. The public endpoint selects only the explicit public number and never falls back to the account number. Anonymous identity, listings, and generic user-management DTOs are unchanged. The viewing helper was extracted without changing its validation or the existing Approved-only tenant-phone policy.

4. **Landlord settings UX:** Web Edit Profile adds the public contact field, explicit visibility checkbox, and privacy helper using the requested wording. Flutter Profile adds a landlord-only public contact editor alongside its existing read-only account details; opening the editor fetches authoritative self-profile data. Both clients validate before saving, wait for API success, retain inputs after failure, and start with an empty public field unless a previously saved public number exists. Tenant, Admin, and Technician settings remain hidden. No optional account-phone copy button was added.

5. **Tenant contact endpoint:** `GET /api/properties/{propertyId}/landlord-contact` returns `{displayName, phoneNumber}` only when enabled and valid; otherwise `204 No Content` for unavailable contact. An unknown property or invalid/inactive associated landlord returns `404`. Responses use `Cache-Control: no-store`.

6. **Backend authorization:** The contact endpoint requires an authenticated Tenant (`401` anonymous; `403` other roles). Existing authentication validates active users. Owner settings are read/written through authenticated `/api/auth/me` and `PUT /api/auth/profile`, using the current authenticated user's identity. Other roles attempting to edit these settings receive `400` and no mutation. No generic landlord/user lookup endpoint was introduced. Omitted contact settings preserve old-client compatibility; an empty string clears the stored number while disabled.

7. **React Property Details:** The Tenant Listed by section loads protected contact independently and conditionally renders Contact landlord. Unavailable, failed, or invalid contact responses omit the section. Returning focus/visibility causes authoritative refetch; prior values clear during refresh and stale requests cannot overwrite newer results.

8. **React Landlord Profile:** Keeps public identity and safe listings separate. Only Tenant users issue the protected property-scoped contact request. Profile retry, remount, and focus/visibility refresh contact. Failed contact requests leave the identity/listings experience usable.

9. **Web plain text:** Both contact sections use a text paragraph. There is no `tel:` link, Call button, WhatsApp, SMS, or email action.

10. **Flutter Property Details:** Optional olive/cream contact card displays the real public number and Call landlord button only after a successful authenticated contact fetch. Contact refreshes on app resume and alongside existing property refreshes/return navigation.

11. **Flutter Landlord Profile:** Uses the same optional contact card. Pull refresh, return from another property, and app resume fetch authoritative contact. Disabled, missing, malformed, or rejected contact requests show no contact card or fake call button. No email is displayed.

12. **Call landlord:** Validates the number, removes display punctuation, constructs a safe `tel:` URI, and uses existing `url_launcher` with external-application mode. The native dialer handles the user's confirmation. No direct-call permission or automatic call was added. False/exception launcher failures show “Calling is not available on this device.” and retain the visible number.

13. **Files changed:** See the complete file list below. Generated logs, inspected SQL, and APK are ignored workspace artifacts.

14. **Backend results:** Restore passed. Release API/test build passed with zero warnings/errors. Focused profile/contact/public-summary/viewing-privacy group: 76 passed; latest contact-only run: 25 passed. Full backend suite: 704 passed, 7 skipped, 0 failed (711 total). Skipped PostgreSQL integration tests require `RENTFLOW_TEST_POSTGRES_CONNECTION_STRING`. EF pending-model check passed; migration SQL inspected.

15. **React results:** ESLint passed. Focused Profile/Property Details/Public Landlord Profile tests: 53 passed. Full web suite: 516 passed across 52 files. Production build passed, with the bundler's chunk-size advisory.

16. **Flutter results:** Analysis passed with no issues. Existing focused profile/property group: 52 passed; new contact/dialer tests: 16 passed; new editor tests: 5 passed. Full Flutter suite: 351 passed. Debug APK build passed; output: `mobile/rentflow_mobile/build/app/outputs/flutter-apk/app-debug.apk`. Tests cover dialer success/failure/exception, protected fetches, safe URI construction, omission, refresh/revocation, stale responses, owner save success/failure, and large text/narrow layout. Android manifests contain no `CALL_PHONE` permission.

17. **Remaining limitations:** Database migration awaits normal deployment. PostgreSQL integration checks were skipped because no disposable test database is configured. Dialer behavior was validated with launcher mocks and an APK build; no physical-device call flow was exercised. `git diff --check` returned success; the full-workspace command reported existing inaccessible agent pytest paths, while the backend/web/mobile/docs check was clean. Unrelated agent artifacts were untouched.

## Complete changed file list

Paths are relative to the repository root. New files are marked **new**.

| Backend file | Change |
| --- | --- |
| `backend/RentFlow.Api/Models/ApplicationUser.cs` | Model fields |
| `backend/RentFlow.Api/Data/ApplicationDbContext.cs` | Column configuration |
| `backend/RentFlow.Api/Data/Migrations/20261003110524_AddLandlordPublicContact.cs` | **new** additive migration |
| `backend/RentFlow.Api/Data/Migrations/20261003110524_AddLandlordPublicContact.Designer.cs` | **new** generated model |
| `backend/RentFlow.Api/Data/Migrations/ApplicationDbContextModelSnapshot.cs` | Updated snapshot |
| `backend/RentFlow.Api/DTOs/Auth/UpdateProfileRequestDto.cs` | Owner update fields |
| `backend/RentFlow.Api/DTOs/Auth/UserProfileDto.cs` | Owner read fields |
| `backend/RentFlow.Api/Services/AuthService.cs` | Owner validation and persistence |
| `backend/RentFlow.Api/Services/PhoneNumberValidation.cs` | **new** shared existing validation |
| `backend/RentFlow.Api/Services/ViewingService.cs` | Reuse extracted helper; privacy policy unchanged |
| `backend/RentFlow.Api/DTOs/LandlordContactDto.cs` | **new** narrow response |
| `backend/RentFlow.Api/Controllers/PropertyLandlordContactsController.cs` | **new** Tenant endpoint |
| `backend/RentFlow.Api.Tests/Authentication/LandlordPublicContactEndpointsTests.cs` | **new** security and persistence tests |

| React file | Change |
| --- | --- |
| `web/rentflow-web/src/features/auth/authModel.js` | Parse owner contact settings |
| `web/rentflow-web/src/shared/pages/ProfilePage.jsx` | Landlord editor |
| `web/rentflow-web/src/shared/pages/profile.css` | Editor styling |
| `web/rentflow-web/src/shared/pages/ProfilePage.test.jsx` | Editor and role tests |
| `web/rentflow-web/src/features/properties/services/propertyApiService.js` | Protected contact request |
| `web/rentflow-web/src/features/properties/publicContactPhone.js` | **new** phone validation |
| `web/rentflow-web/src/features/properties/components/LandlordContact.jsx` | **new** optional contact and refresh |
| `web/rentflow-web/src/features/properties/components/landlord-contact.css` | **new** contact styling |
| `web/rentflow-web/src/features/properties/pages/PropertyDetailsPage.jsx` | Details contact integration |
| `web/rentflow-web/src/features/properties/pages/PropertyDetailsPage.test.jsx` | Text-only and omission tests |
| `web/rentflow-web/src/features/properties/pages/PublicLandlordProfilePage.jsx` | Profile contact integration |
| `web/rentflow-web/src/features/properties/pages/PublicLandlordProfilePage.test.jsx` | Protected contact, role, and refresh tests |

| Flutter file | Change |
| --- | --- |
| `mobile/rentflow_mobile/lib/core/validation/phone_number.dart` | **new** phone validation |
| `mobile/rentflow_mobile/lib/features/auth/models/current_user.dart` | Owner contact settings |
| `mobile/rentflow_mobile/lib/features/auth/services/auth_service.dart` | Owner update API |
| `mobile/rentflow_mobile/lib/features/auth/controllers/auth_controller.dart` | Accept successful owner saves |
| `mobile/rentflow_mobile/lib/shared/profile/shared_profile_content.dart` | Landlord-only settings entry |
| `mobile/rentflow_mobile/lib/shared/profile/public_contact_editor.dart` | **new** authoritative editor |
| `mobile/rentflow_mobile/lib/features/properties/models/landlord_contact.dart` | **new** safe contact parser |
| `mobile/rentflow_mobile/lib/features/properties/services/property_api_service.dart` | Authenticated contact fetch |
| `mobile/rentflow_mobile/lib/features/properties/widgets/landlord_contact_card.dart` | **new** optional contact/dialer card |
| `mobile/rentflow_mobile/lib/features/properties/screens/property_details_screen.dart` | Details integration and refresh |
| `mobile/rentflow_mobile/lib/features/properties/screens/public_landlord_profile_screen.dart` | Profile integration and refresh |
| `mobile/rentflow_mobile/test/landlord_public_contact_test.dart` | **new** contact/dialer/refresh/layout tests |
| `mobile/rentflow_mobile/test/public_contact_editor_test.dart` | **new** owner editing tests |

| Documentation file | Change |
| --- | --- |
| `docs/landlord-public-contact-report.md` | **new** implementation and validation report |
