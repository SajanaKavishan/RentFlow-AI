import { ApiError, apiRequest } from '../../../core/api/apiClient.js'

export const VIEWING_STATUS = Object.freeze({
  PENDING: 0,
  APPROVED: 1,
  REJECTED: 2,
  CANCELLED: 3,
  COMPLETED: 4,
})

export class ViewingApiError extends ApiError {
  constructor(message, statusCode = null) {
    super(message)
    this.name = 'ViewingApiError'
    this.statusCode = statusCode
  }
}

async function request(path, options = {}) {
  try {
    return await apiRequest(path, {
      ...options,
      errorMessage: 'The viewing request failed. Please try again.',
      networkErrorMessage: 'Unable to connect to the viewing service. Please try again.',
    })
  } catch (error) {
    if (error instanceof ApiError) throw new ViewingApiError(error.message, error.statusCode)
    throw error
  }
}

export function getViewingsByProperty(propertyId) {
  return request(`/api/viewings/property/${encodeURIComponent(propertyId)}`)
}

export function getViewingById(id) {
  return request(`/api/viewings/${encodeURIComponent(id)}`)
}

export function approveViewing(id, landlordResponse = '') {
  return request(`/api/viewings/${encodeURIComponent(id)}/approve`, {
    method: 'PATCH',
    body: JSON.stringify({
      status: VIEWING_STATUS.APPROVED,
      landlordResponse: landlordResponse.trim() || null,
    }),
  })
}

export function rejectViewing(id, landlordResponse) {
  return request(`/api/viewings/${encodeURIComponent(id)}/reject`, {
    method: 'PATCH',
    body: JSON.stringify({
      status: VIEWING_STATUS.REJECTED,
      landlordResponse: landlordResponse.trim(),
    }),
  })
}
