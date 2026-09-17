# Lease Agreement Backend

## Overview

The Lease Agreement feature manages the creation and lifecycle of lease agreements after a tenant accepts a rental offer.

The workflow is:

Approved Rental Application
→ Rental Offer
→ Accepted Rental Offer
→ Lease Agreement

A lease agreement cannot be created directly without an accepted rental offer.

## Domain Model

### LeaseAgreement

The LeaseAgreement entity stores:

- Id
- RentalOfferId
- TenantId
- PropertyId
- MonthlyRent
- SecurityDeposit
- StartDate
- EndDate
- Status
- CreatedAt
- UpdatedAt

Lease agreement financial and property information is copied from the accepted rental offer.

This prevents clients from changing the agreed rental terms when creating the lease.

## Lease Agreement Status

The supported statuses are:

- Pending
- Active
- Terminated
- Completed

### Status Meaning

Pending:
The lease has been created but is not yet active.

Active:
The lease is currently active.

Terminated:
The lease was ended before normal completion.

Completed:
The lease completed normally.

## Main Business Rules

### Lease Creation

A lease agreement can only be created when:

- the rental offer exists
- the rental offer status is Accepted
- another lease does not already exist for the same rental offer
- the lease start and end dates are valid

The following values are copied directly from the accepted rental offer:

- TenantId
- PropertyId
- MonthlyRent
- SecurityDeposit
- ProposedStartDate → StartDate
- ProposedEndDate → EndDate

A newly created lease starts with the status:

Pending

### Lease Activation

Only a Pending lease can be activated.

Transition:

Pending → Active

### Lease Termination

Only an Active lease can be terminated.

Transition:

Active → Terminated

### Lease Completion

Only an Active lease can be completed.

Transition:

Active → Completed

## API Endpoints

### Create Lease Agreement

POST /api/lease-agreements

Allowed roles:

- Landlord
- Admin

Request example:

```json
{
  "rentalOfferId": "00000000-0000-0000-0000-000000000000"
}