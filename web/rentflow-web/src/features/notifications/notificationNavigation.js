import { USER_ROLES } from '../auth/authModel.js'
import { getApplicationById } from '../rentalApplications/services/rentalApplicationApiService.js'
import { getViewingById } from '../viewings/services/viewingApiService.js'
import { getMaintenanceRequestById } from '../maintenance/services/maintenanceApiService.js'
import { getRentalOffer } from '../rentalOffers/services/rentalOfferApiService.js'
import { getLeaseAgreement } from '../leaseAgreements/services/leaseAgreementApiService.js'
import { getPayment } from '../payments/services/paymentApiService.js'

const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export class NotificationDestinationError extends Error {
  constructor(message) {
    super(message)
    this.name = 'NotificationDestinationError'
  }
}

export async function notificationDestination(notification, role) {
  const landlordEvents = {
    'maintenance_request.submitted': ['MaintenanceRequest', getMaintenanceRequestById],
    'maintenance_request.triaged': ['MaintenanceRequest', getMaintenanceRequestById],
    'maintenance_request.estimate_preparation': ['MaintenanceRequest', getMaintenanceRequestById],
    'maintenance_request.estimate_review': ['MaintenanceRequest', getMaintenanceRequestById],
    'maintenance_request.coordination_review': ['MaintenanceRequest', getMaintenanceRequestById],
    'rental_offer.accepted': ['RentalOffer', getRentalOffer],
    'lease.activation_required': ['LeaseAgreement', getLeaseAgreement],
    'payment.manual_review': ['Payment', getPayment],
  }
  const event = landlordEvents[notification.eventType]
  if (event) {
    if (role !== USER_ROLES.LANDLORD || notification.relatedResourceType !== event[0]) return null
    const id = notification.relatedResourceId
    if (typeof id !== 'string' || !GUID.test(id)) throw new NotificationDestinationError('This notification has no supported destination.')
    const resource = await event[1](id)
    if (typeof resource?.id !== 'string' || resource.id.toLowerCase() !== id.toLowerCase()) throw new NotificationDestinationError('The related record could not be verified.')
    if (event[0] === 'MaintenanceRequest') {
      if (typeof resource.propertyId !== 'string' || !GUID.test(resource.propertyId)) throw new NotificationDestinationError('The related property could not be verified.')
      return `/properties/${encodeURIComponent(resource.propertyId)}/maintenance?${new URLSearchParams({ requestId: id })}`
    }
    if (event[0] === 'Payment') return `/modules/payments?${new URLSearchParams({ paymentId: id })}`
    return `/modules/pricing-lease/leases?${new URLSearchParams({ [event[0] === 'RentalOffer' ? 'rentalOfferId' : 'leaseId']: id })}`
  }
  if (notification.eventType === 'maintenance_technician.activated') return null
  if (notification.eventType === 'maintenance_request.assigned') {
    if (role !== USER_ROLES.MAINTENANCE_TECHNICIAN || notification.relatedResourceType !== 'MaintenanceRequest') return null
    if (typeof notification.relatedResourceId !== 'string' || !GUID.test(notification.relatedResourceId)) {
      throw new NotificationDestinationError('This notification has no supported destination.')
    }
    const request = await getMaintenanceRequestById(notification.relatedResourceId)
    if (!request || request.id.toLowerCase() !== notification.relatedResourceId.toLowerCase()) {
      throw new NotificationDestinationError('The related maintenance request could not be verified.')
    }
    return `/modules/assigned-work?requestId=${encodeURIComponent(notification.relatedResourceId)}`
  }

  const { relatedResourceType: type, relatedResourceId: id } = notification
  const supportsApplication = type === 'RentalApplication' && [USER_ROLES.TENANT, USER_ROLES.LANDLORD].includes(role)
  const supportsViewing = type === 'ViewingRequest' && [USER_ROLES.TENANT, USER_ROLES.LANDLORD].includes(role)
  if (!supportsApplication && !supportsViewing) return null

  if (typeof id !== 'string' || !GUID.test(id)) {
    throw new NotificationDestinationError('This notification has no supported destination.')
  }

  let resource
  let path
  if (supportsApplication) {
    resource = await getApplicationById(id)
    path = `/notifications/rental-application/${encodeURIComponent(id)}`
  } else {
    resource = await getViewingById(id)
    path = role === USER_ROLES.TENANT
      ? '/modules/my-viewings'
      : `/notifications/viewing-request/${encodeURIComponent(id)}`
  }

  if (!resource || typeof resource.id !== 'string' || resource.id.toLowerCase() !== id.toLowerCase()) {
    throw new NotificationDestinationError('The related record could not be verified.')
  }
  return path
}

export function notificationNavigationError(error) {
  if (error instanceof NotificationDestinationError) return error.message
  if (error?.statusCode === 403 || error?.statusCode === 404) {
    return 'The related record is unavailable or you do not have access to it.'
  }
  return 'The related record could not be opened. Please try again.'
}
