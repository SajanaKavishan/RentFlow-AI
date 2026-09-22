import { USER_ROLES } from '../auth/authModel.js'
import { getApplicationById } from '../rentalApplications/services/rentalApplicationApiService.js'
import { getViewingById } from '../viewings/services/viewingApiService.js'

const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export class NotificationDestinationError extends Error {
  constructor(message) {
    super(message)
    this.name = 'NotificationDestinationError'
  }
}

export async function notificationDestination(notification, role) {
  const { relatedResourceType: type, relatedResourceId: id } = notification
  if (typeof id !== 'string' || !GUID.test(id)) {
    throw new NotificationDestinationError('This notification has no supported destination.')
  }

  let resource
  let path
  if (type === 'RentalApplication' && [USER_ROLES.TENANT, USER_ROLES.LANDLORD].includes(role)) {
    resource = await getApplicationById(id)
    path = `/notifications/rental-application/${encodeURIComponent(id)}`
  } else if (type === 'ViewingRequest' && [USER_ROLES.TENANT, USER_ROLES.LANDLORD].includes(role)) {
    resource = await getViewingById(id)
    path = role === USER_ROLES.TENANT
      ? '/modules/my-viewings'
      : `/notifications/viewing-request/${encodeURIComponent(id)}`
  } else {
    throw new NotificationDestinationError('This notification has no supported destination.')
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
