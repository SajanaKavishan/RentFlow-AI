import { apiRequest } from '../../../core/api/apiClient.js'

const path = (id) => `/api/lease-agreements/${encodeURIComponent(id)}`

export function getLandlordLeases() {
  return apiRequest('/api/lease-agreements/landlord', { errorMessage: 'Unable to load lease agreements.' })
}

export function createLeaseAgreement(rentalOfferId) {
  return apiRequest('/api/lease-agreements', {
    method: 'POST',
    body: JSON.stringify({ rentalOfferId }),
    errorMessage: 'Unable to create the lease agreement.',
  })
}

export function getLeaseAgreement(id) {
  return apiRequest(path(id), { errorMessage: 'Unable to load the lease agreement.' })
}

export function changeLeaseStatus(id, action) {
  if (!['activate', 'terminate', 'complete'].includes(action)) throw new TypeError('Unsupported lease action.')
  return apiRequest(`${path(id)}/${action}`, {
    method: 'PATCH',
    errorMessage: 'Unable to update the lease agreement.',
  })
}
