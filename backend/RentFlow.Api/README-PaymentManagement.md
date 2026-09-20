# Payment Management Backend

## Overview

The Payment Management feature handles tenant rent payments for generated rent schedule items.

The workflow is:

Approved Rental Application
→ Rental Offer
→ Accepted Rental Offer
→ Lease Agreement
→ Active Lease
→ Rent Schedule
→ Payment

A payment is always linked to a RentScheduleItem.

## Domain Model

### Payment

The Payment entity stores:

- Id
- RentScheduleItemId
- TenantId
- Amount
- PaymentMethod
- TransactionReference
- Status
- PaidAt
- CreatedAt
- UpdatedAt

The payment amount is not entered by the client.

The backend copies the amount directly from the related RentScheduleItem.

This prevents the client from changing the expected rent amount.

## Payment Status

Supported statuses are:

- Pending
- Completed
- Failed

### Status Meaning

Pending:
The payment has been created but has not yet been completed.

Completed:
The payment was successfully completed.

Failed:
The payment attempt failed.

## Main Business Rules

### Payment Creation

A payment can only be created when:

- the rent schedule item exists
- the rent schedule item belongs to the authenticated tenant
- the rent schedule item has not already been paid
- another completed payment does not already exist for the same rent schedule item
- a valid payment method is provided

The backend automatically uses:

- TenantId from the authenticated user
- Amount from the RentScheduleItem

The client does not manually provide TenantId or Amount.

A newly created payment starts with:

Pending

### Payment Completion

Only a Pending payment can be completed.

Transition:

Pending → Completed

When a payment is completed:

- Payment Status becomes Completed
- PaidAt is recorded
- UpdatedAt is recorded
- the related RentScheduleItem becomes Paid

This keeps the payment and rent schedule synchronized.

### Payment Failure

Only a Pending payment can be marked as failed.

Transition:

Pending → Failed

When a payment fails:

- Payment Status becomes Failed
- UpdatedAt is recorded
- the related RentScheduleItem remains Pending

## API Endpoints

### Create Payment

POST /api/payments

Allowed role:

- Tenant

Request example:

```json
{
  "rentScheduleItemId": "00000000-0000-0000-0000-000000000000",
  "paymentMethod": "BankTransfer",
  "transactionReference": "TXN-001"
}