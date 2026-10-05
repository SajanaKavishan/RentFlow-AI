import { ApiError, apiRequest } from '../../../core/api/apiClient.js'

export const RENTAL_APPLICATION_STATUS = Object.freeze({
  DRAFT: 0,
  SUBMITTED: 1,
  UNDER_REVIEW: 2,
  CHANGES_REQUESTED: 3,
  APPROVED: 4,
  REJECTED: 5,
  WITHDRAWN: 6,
})

export class RentalApplicationApiError extends ApiError {
  constructor(message, statusCode = null) {
    super(message)
    this.name = 'RentalApplicationApiError'
    this.statusCode = statusCode
  }
}

async function request(path, options = {}) {
  try {
    return await apiRequest(path, {
      ...options,
      errorMessage: 'The rental application request failed. Please try again.',
      networkErrorMessage: 'Unable to connect to the rental application service. Please try again.',
    })
  } catch (error) {
    if (error instanceof ApiError) throw new RentalApplicationApiError(error.message, error.statusCode)
    throw error
  }
}

function applicationPath(id, action = '') {
  const encodedId = encodeURIComponent(id)
  return `/api/rental-applications/${encodedId}${action ? `/${action}` : ''}`
}

export function getApplicationsByProperty(propertyId) {
  return request(
    `/api/rental-applications/property/${encodeURIComponent(propertyId)}`,
  )
}

export function getApplicationById(id) {
  return request(applicationPath(id))
}

export function getMyApplications() {
  return request('/api/rental-applications')
}

export async function getApplicationEligibility(propertyId) {
  const result = await request(`/api/properties/${encodeURIComponent(propertyId)}/rental-application-eligibility`)
  if (!result || typeof result.canApply !== 'boolean' || typeof result.hasCompletedViewing !== 'boolean'
    || (result.reason != null && typeof result.reason !== 'string')
    || (result.existingApplicationId != null && (typeof result.existingApplicationId !== 'string' || !result.existingApplicationId.trim()))
    || ((result.existingApplicationId == null) !== (result.existingApplicationStatus == null))
    || (result.existingApplicationStatus != null && !Object.values(RENTAL_APPLICATION_STATUS).includes(result.existingApplicationStatus))
    || (result.canApply && (!result.hasCompletedViewing || result.existingApplicationId != null))) {
    throw new RentalApplicationApiError('Unable to check application eligibility. Please try again.')
  }
  return result
}

export function markUnderReview(id) {
  return request(applicationPath(id, 'review'), { method: 'PATCH' })
}

export function approveApplication(id, landlordResponse = '') {
  return request(applicationPath(id, 'approve'), {
    method: 'PATCH',
    body: JSON.stringify({
      landlordResponse: landlordResponse.trim() || null,
    }),
  })
}

export function rejectApplication(id, landlordReason) {
  return request(applicationPath(id, 'reject'), {
    method: 'PATCH',
    body: JSON.stringify({ landlordResponse: landlordReason.trim() }),
  })
}

export function requestChanges(id, landlordMessage) {
  return request(applicationPath(id, 'request-changes'), {
    method: 'PATCH',
    body: JSON.stringify({ landlordResponse: landlordMessage.trim() }),
  })
}
