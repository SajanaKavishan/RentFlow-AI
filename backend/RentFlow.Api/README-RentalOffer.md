# Rental Offer & Pricing Backend

## Overview

This implementation adds the first backend workflow for Component 3:

**Rental Pricing, Lease & Payment Management**

The workflow begins after a rental application has already been approved.

Current flow:

Approved Rental Application  
→ Rental Offer  
→ Tenant Accepts / Rejects  
→ Future Lease Agreement

This README documents the Rental Offer & Pricing backend implementation completed so far.

---

## Main Purpose

The Rental Offer feature allows a landlord or admin to create a rental offer for an approved rental application.

A tenant can then:

- View their own rental offers
- Accept a pending rental offer
- Reject a pending rental offer

A landlord or admin can also withdraw a pending rental offer.

---

## Important Files

### Models

`Models/RentalOffer.cs`

Represents a rental offer stored in the database.

Important fields include:

- RentalApplicationId
- TenantId
- PropertyId
- MonthlyRent
- SecurityDeposit
- ProposedStartDate
- ProposedEndDate
- ExpiresAt
- Status
- LandlordNote
- CreatedAt
- UpdatedAt

---

`Models/RentalOfferStatus.cs`

Defines the rental offer workflow states:

- Pending
- Accepted
- Rejected
- Withdrawn
- Expired

---

## DTOs

`DTOs/RentalOffers/CreateRentalOfferDto.cs`

Defines the request data required when creating a rental offer.

The client provides:

- RentalApplicationId
- MonthlyRent
- SecurityDeposit
- ProposedStartDate
- ProposedEndDate
- ExpiresAt
- LandlordNote

The client does not provide TenantId, PropertyId, Status, CreatedAt, or UpdatedAt.

These values are controlled by the backend.

---

`DTOs/RentalOffers/RentalOfferResponseDto.cs`

Defines the rental offer information returned by the API.

---

## Service Layer

`Services/Interfaces/IRentalOfferService.cs`

Defines the Rental Offer service operations.

Current operations:

- CreateAsync
- GetByIdAsync
- GetByTenantAsync
- AcceptAsync
- RejectAsync
- WithdrawAsync

---

`Services/RentalOfferService.cs`

Contains the main Rental Offer business logic.

Important business rules include:

1. A rental offer can only be created from an approved rental application.

2. Monthly rent must be greater than zero.

3. Security deposit cannot be negative.

4. Proposed end date must be after the proposed start date.

5. Offer expiry must be in the future.

6. Only one pending rental offer is allowed for the same rental application.

7. TenantId and PropertyId are copied from the approved rental application instead of being trusted from the client.

8. Only the tenant who owns the offer can accept or reject it.

9. Only pending rental offers can be accepted, rejected, or withdrawn.

10. An expired rental offer cannot be accepted or rejected.

---

## API Controller

`Controllers/RentalOffersController.cs`

Base route:

`/api/rental-offers`

### Create Rental Offer

`POST /api/rental-offers`

Allowed roles:

- Landlord
- Admin

Creates a rental offer from an approved rental application.

Successful response:

`201 Created`

---

### Get Current Tenant's Offers

`GET /api/rental-offers/mine`

Allowed role:

- Tenant

Uses the authenticated user's ID from the JWT.

This prevents a tenant from requesting another tenant's offers by manually changing an ID.

---

### Get Rental Offer by ID

`GET /api/rental-offers/{id}`

Allowed roles:

- Tenant
- Landlord
- Admin

Returns a rental offer by ID.

---

### Accept Rental Offer

`PATCH /api/rental-offers/{id}/accept`

Allowed role:

- Tenant

Changes:

`Pending → Accepted`

The service verifies that the authenticated tenant owns the offer.

---

### Reject Rental Offer

`PATCH /api/rental-offers/{id}/reject`

Allowed role:

- Tenant

Changes:

`Pending → Rejected`

---

### Withdraw Rental Offer

`PATCH /api/rental-offers/{id}/withdraw`

Allowed roles:

- Landlord
- Admin

Changes:

`Pending → Withdrawn`

---

## Database

The Rental Offer entity is registered in:

`Data/ApplicationDbContext.cs`

The migration used to create the RentalOffers table is:

`AddRentalOffers`

The table includes indexes for:

- RentalApplicationId
- TenantId
- PropertyId
- Status

RentalApplicationId is a foreign key to RentalApplications.

---

## Error Handling

Rental Offer service errors are represented using:

`RentalOfferServiceException`

Current error types:

- Validation
- NotFound
- Conflict

The controller maps these to HTTP responses:

- Validation → 400 Bad Request
- NotFound → 404 Not Found
- Conflict → 409 Conflict

Unexpected errors return:

- 500 Internal Server Error

---

## Automated Tests

Service tests:

`RentFlow.Api.Tests/Services/RentalOfferServiceTests.cs`

These tests cover:

- Creating an offer for an approved application
- Rejecting offer creation for a non-approved application
- Rejecting duplicate pending offers
- Accepting a pending offer
- Preventing another tenant from accepting an offer
- Expired offer handling
- Rejecting a pending offer
- Withdrawing a pending offer

Controller tests:

`RentFlow.Api.Tests/Controllers/RentalOffersControllerTests.cs`

These tests cover:

- 201 response when creating an offer
- Getting an existing offer
- 404 response for a missing offer
- Using the authenticated tenant ID for "my offers"
- Using the authenticated tenant ID when accepting an offer
- Mapping service conflicts to HTTP 409 responses

---

## How to Run the Tests

From the repository root:

```powershell
dotnet test .\backend\RentFlow.Api.Tests\RentFlow.Api.Tests.csproj