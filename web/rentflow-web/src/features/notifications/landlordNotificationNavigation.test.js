import { beforeEach, expect, it, vi } from 'vitest'
import { notificationDestination } from './notificationNavigation.js'
import { getMaintenanceRequestById } from '../maintenance/services/maintenanceApiService.js'
import { getRentalOffer } from '../rentalOffers/services/rentalOfferApiService.js'
import { getLeaseAgreement } from '../leaseAgreements/services/leaseAgreementApiService.js'
import { getPayment } from '../payments/services/paymentApiService.js'
vi.mock('../maintenance/services/maintenanceApiService.js', () => ({ getMaintenanceRequestById: vi.fn() }))
vi.mock('../rentalOffers/services/rentalOfferApiService.js', () => ({ getRentalOffer: vi.fn() }))
vi.mock('../leaseAgreements/services/leaseAgreementApiService.js', () => ({ getLeaseAgreement: vi.fn() }))
vi.mock('../payments/services/paymentApiService.js', () => ({ getPayment: vi.fn() }))
const id = '11111111-1111-4111-8111-111111111111', propertyId = '22222222-2222-4222-8222-222222222222'
beforeEach(() => { vi.resetAllMocks(); [getMaintenanceRequestById, getRentalOffer, getLeaseAgreement, getPayment].forEach((method) => method.mockResolvedValue({ id, propertyId })) })
it.each([
  ['maintenance_request.submitted', 'MaintenanceRequest', `/properties/${propertyId}/maintenance?requestId=${id}`],
  ['maintenance_request.estimate_review', 'MaintenanceRequest', `/properties/${propertyId}/maintenance?requestId=${id}`],
  ['maintenance_request.coordination_review', 'MaintenanceRequest', `/properties/${propertyId}/maintenance?requestId=${id}`],
  ['rental_offer.accepted', 'RentalOffer', `/modules/pricing-lease/leases?rentalOfferId=${id}`],
  ['lease.activation_required', 'LeaseAgreement', `/modules/pricing-lease/leases?leaseId=${id}`],
  ['payment.manual_review', 'Payment', `/modules/payments?paymentId=${id}`],
])('opens the authorized resource for %s', async (eventType, relatedResourceType, expected) => {
  const event = { eventType, relatedResourceType, relatedResourceId: id }
  expect(await notificationDestination(event, 'Landlord')).toBe(expected)
  expect(await notificationDestination(event, 'Tenant')).toBeNull()
})
it('does not navigate to an inaccessible or mismatched resource', async () => {
  const event = { eventType: 'payment.manual_review', relatedResourceType: 'Payment', relatedResourceId: id }
  getPayment.mockRejectedValueOnce(Object.assign(new Error('Forbidden'), { statusCode: 403 }))
  await expect(notificationDestination(event, 'Landlord')).rejects.toThrow('Forbidden')
  getPayment.mockResolvedValueOnce({ id: propertyId })
  await expect(notificationDestination(event, 'Landlord')).rejects.toThrow('could not be verified')
})
