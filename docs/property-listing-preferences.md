# Property listing preferences

Property listing preferences are public, pre-application information. They are
non-binding and are never copied automatically into `RentalOffer` or
`LeaseAgreement`; those modules remain authoritative for proposed and accepted
terms respectively.

The legacy `PUT /api/properties/{id}` contract remains available and does not
contain or modify the newer listing-preference fields. The React Add/Edit flow
uses `PUT /api/properties/{id}/listing` with `UpdatePropertyListingDto`, which
updates core listing data, preferences, utilities, and amenities atomically.

`IncludedUtilities` uses a nullable PostgreSQL `text[]`: `null` means no utility
information was provided, while an empty array explicitly means none are
included. The catalog is `water`, `electricity`, `internet`, `gas`, and
`waste-collection`.

Canonical amenities are stored as stable nullable keys alongside the original
display/custom `Name`. API responses retain the legacy `amenities: string[]`
and add `amenityDetails`. Unknown custom names remain visible and editable.
