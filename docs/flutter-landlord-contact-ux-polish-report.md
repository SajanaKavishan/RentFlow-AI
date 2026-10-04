# Flutter landlord contact and Property Details UX report

Validated on 4 October 2026. All work stayed on the current branch, with no branch operations, commits, pushes, or PRs.

1. **Final landlord page header:** a bare accessible Back arrow followed by an olive `LANDLORD` eyebrow (11px) and `Other properties` title (22px, semibold). The toolbar grows to fit wrapped text at larger accessibility scales.

2. **Duplicate landlord name removed:** the app bar no longer uses the landlord name, including during loading and errors. The name appears once in the identity card. Tests verify both the single name and its absence from the app bar.

3. **Final identity card:** a compact white card with 12px padding, a 56px public photo/initials avatar, an 18px semibold name, a 13px membership line, and a 13px rating/count line only when the existing public landlord-review endpoint supplies a real, nonempty aggregate. Both screens reuse `PublicLandlordIdentity`. Long names wrap; at large text scales, the avatar and identity stack without clamping text scaling.

4. **Compact contact design:** both screens reuse the existing `LandlordContactCard`. Its white card contains a 16px title and one selectable 14px phone number beside an olive phone icon on a cream background. The icon has a 44px minimum visual size and a padded accessible tap target. The number wraps within the available width. There is no full-width call button, duplicated number, WhatsApp action, or SMS action.

5. **Phone icon/dialer behavior:** the icon explicitly exposes the semantic label and tooltip `Call landlord`. It invokes the unchanged safe `tel:` URI helper and `LaunchMode.externalApplication` flow. Tests verify the sanitized URI, external launch, tap semantics, and failure feedback. Calling remains user-confirmed in the native dialer. Contact still fails closed, refreshes after resume, and disappears when public contact is disabled or invalid; private account contact never becomes a fallback.

6. **Property Details Listed-by area:** retains the avatar, single landlord name, membership, real landlord rating, and `View other properties` navigation. It now uses the shared compact identity layout and compact contact row, with a 15px navigation action and preserved navigation semantics.

7. **Other-properties typography and hierarchy:** identity → optional contact → optional real landlord experience/comments → other properties/count/cards. The title is 22px semibold, identity name 18px semibold, section heading 17px semibold, membership/count/rating 13px, and phone 14px. Existing property-card titles remain 16px. Hidden contact/reviews create no extra section gap; the no-contact/no-rating case has 16px between identity and the listings heading. No app-wide type scale changed.

8. **Bottom CTA changes:** Property Details opts out of the normal ineligible helper through the shared action's presentation-only `showIneligibleReason` option. The existing outlined olive Book Viewing button and muted disabled Apply after viewing button remain aligned. Safe-area spacing, backend eligibility checks, active Apply Now styling, and Continue/View application destinations are preserved. Eligibility errors still show their feedback and retry action.

9. **Helper paragraph removed:** `Complete a viewing before applying for this property.` is no longer rendered below Apply after viewing on Property Details. The unavailable-property state also avoids a second redundant eligibility reason while keeping its existing availability notice. Other consumers of the shared eligibility action retain their default presentation.

10. **Files changed:** six implementation files, five regression-test files, and this report.

| File | Change |
| --- | --- |
| [public_landlord_profile_screen.dart](../mobile/rentflow_mobile/lib/features/properties/screens/public_landlord_profile_screen.dart) | Contextual header, compact identity, shared real review aggregate, spacing and section typography |
| [property_details_screen.dart](../mobile/rentflow_mobile/lib/features/properties/screens/property_details_screen.dart) | Shared Listed-by identity and bottom helper suppression |
| [landlord_contact_card.dart](../mobile/rentflow_mobile/lib/features/properties/widgets/landlord_contact_card.dart) | Single phone row and accessible call icon |
| [public_landlord_identity.dart](../mobile/rentflow_mobile/lib/features/properties/widgets/public_landlord_identity.dart) | New shared responsive identity widget |
| [viewing_rating_summary.dart](../mobile/rentflow_mobile/lib/features/viewing_reviews/widgets/viewing_rating_summary.dart) | Optional compact rating typography |
| [application_eligibility_action.dart](../mobile/rentflow_mobile/lib/features/rental_applications/widgets/application_eligibility_action.dart) | Presentation-only opt-out for normal ineligible helper |
| [property_details_test.dart](../mobile/rentflow_mobile/test/property_details_test.dart) | Single unavailable-state notice expectation |
| [public_landlord_profile_screen_test.dart](../mobile/rentflow_mobile/test/public_landlord_profile_screen_test.dart) | Header, single identity, compact avatar/contact, absence of fake rating, spacing and layout coverage |
| [landlord_public_contact_test.dart](../mobile/rentflow_mobile/test/landlord_public_contact_test.dart) | Icon action, semantics, privacy, dialer and long-content device matrix |
| [application_eligibility_test.dart](../mobile/rentflow_mobile/test/application_eligibility_test.dart) | Removed helper, disabled semantics, aligned CTAs and bottom safe area |
| [viewing_reviews_public_test.dart](../mobile/rentflow_mobile/test/viewing_reviews_public_test.dart) | Real-only landlord identity aggregate with existing review/comment coverage |
| [This report](flutter-landlord-contact-ux-polish-report.md) | Requested implementation and validation report |

11. **Focused tests:** all **106 passed** across Property Details, Property Details redesign, public landlord profile, landlord public contact/dialer, application eligibility, and public viewing reviews. Coverage includes 320px width, 720×1560 at DPR 2, 1080×2340 at DPR 3, normal/200% text scaling, long names/numbers, phone wrapping, missing ratings/contact, one/multiple listings, navigation/favorites, and preserved eligibility behavior.

12. **Full Flutter suite:** `flutter test --reporter expanded` — all **812 passed**, zero failures.

13. **Analyze/APK/diff check:** `flutter analyze` — no issues. `flutter build apk --debug` — succeeded; output is `mobile/rentflow_mobile/build/app/outputs/flutter-apk/app-debug.apk`. `git diff --check` — exit 0, no whitespace errors; the Flutter-scoped check also passed. Validation logs are retained locally as ignored `contact-ux-*.log` files in the mobile project. The build emitted a nonfatal Java/Gradle native-access warning. The repository-wide Git check also reported pre-existing permission warnings for unrelated Python pytest temporary paths; those paths were left untouched.

14. **Remaining limitations:** validation used widget tests, mocked API/platform responses, static analysis, and a debug APK build. A physical-device dialer launch and manual TalkBack/device visual inspection were not performed. No backend contact/privacy rules, application/viewing eligibility, scheduling, reviews, favorites, or property navigation rules were changed, and no production contact/review data was fabricated.
