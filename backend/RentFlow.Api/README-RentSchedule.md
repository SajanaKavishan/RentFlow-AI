# Rent Schedule Backend

## Overview

The Rent Schedule feature generates and manages monthly rent obligations for an active lease agreement.

The workflow is:

Accepted Rental Offer
→ Lease Agreement
→ Active Lease
→ Rent Schedule
→ Payment Management

A rent schedule cannot be generated unless the lease agreement is active.

## Domain Model

### RentScheduleItem

Each RentScheduleItem represents one scheduled monthly rent payment.

It stores:

- Id
- LeaseAgreementId
- DueDate
- Amount
- Status
- CreatedAt
- UpdatedAt

One lease agreement can have multiple rent schedule items.

Example:

October 2026 → Rs. 85,000 → Pending

November 2026 → Rs. 85,000 → Pending

December 2026 → Rs. 85,000 → Pending

## Rent Schedule Status

Supported statuses are:

- Pending
- Paid
- Overdue

### Status Meaning

Pending:
The rent payment is due but has not yet been paid.

Paid:
The rent payment has been successfully paid.

Overdue:
The due date has passed and the rent is still unpaid.

## Main Business Rules

### Schedule Generation

A rent schedule can only be generated when:

- the lease agreement exists
- the lease agreement status is Active
- the monthly rent is greater than zero
- the lease date range is valid
- a rent schedule does not already exist for the lease

The schedule automatically uses:

- LeaseAgreementId
- MonthlyRent
- StartDate
- EndDate

The client does not manually enter each monthly rent item.

### Monthly Schedule Generation

The service starts from the lease StartDate.

It then creates one schedule item every month until the lease EndDate.

For example:

StartDate: 2026-10-01

EndDate: 2027-09-30

MonthlyRent: Rs. 85,000

This creates 12 monthly rent schedule items.

Each newly generated item starts with:

Pending

### Duplicate Prevention

The database uses a unique index for:

LeaseAgreementId + DueDate

This prevents duplicate rent schedule items for the same lease and due date.

The service also checks whether a schedule already exists before generating another one.

## API Endpoints

### Generate Rent Schedule

POST /api/rent-schedules/lease/{leaseAgreementId}/generate

Allowed roles:

- Landlord
- Admin

Generates monthly rent schedule items for an active lease.

### Get Rent Schedule By Lease

GET /api/rent-schedules/lease/{leaseAgreementId}

Allowed roles:

- Tenant
- Landlord
- Admin

Returns all rent schedule items for the specified lease.

### Get Current Tenant Rent Schedule

GET /api/rent-schedules/mine

Allowed role:

- Tenant

Uses the authenticated tenant ID and returns that tenant's rent schedule items.

### Get Rent Schedule Item By ID

GET /api/rent-schedules/{id}

Allowed roles:

- Tenant
- Landlord
- Admin

Returns one rent schedule item.

## Error Handling

The RentScheduleService uses RentScheduleServiceException.

Supported error types:

- Validation
- NotFound
- Conflict

Controller mapping:

Validation → HTTP 400 Bad Request

NotFound → HTTP 404 Not Found

Conflict → HTTP 409 Conflict

Unexpected error → HTTP 500 Internal Server Error

## Database

The RentScheduleItems table was added using Entity Framework Core migration.

Migration:

AddRentScheduleItems

Important database rules:

- LeaseAgreementId is a foreign key to LeaseAgreements
- delete behavior is Restrict
- Amount uses decimal precision 18,2
- LeaseAgreementId + DueDate is unique

Indexes are available for:

- LeaseAgreementId
- DueDate
- Status
- LeaseAgreementId + DueDate

## Main Files

### Models

- Models/RentScheduleItem.cs
- Models/RentScheduleStatus.cs

### DTOs

- DTOs/RentSchedules/RentScheduleItemResponseDto.cs

### Services

- Services/Interfaces/IRentScheduleService.cs
- Services/RentScheduleService.cs
- Services/RentScheduleServiceException.cs

### Controller

- Controllers/RentSchedulesController.cs

### Database

- Data/ApplicationDbContext.cs
- Data/Migrations/*_AddRentScheduleItems.cs

### Tests

- RentFlow.Api.Tests/Services/RentScheduleServiceTests.cs
- RentFlow.Api.Tests/Controllers/RentSchedulesControllerTests.cs

## Tests

Rent Schedule service tests:

5

Rent Schedule controller tests:

5

Total Rent Schedule tests:

10

Current full backend test suite:

170 passed
0 failed
0 skipped

Run all backend tests with:

```powershell
dotnet test