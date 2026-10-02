import { apiRequest } from '../../../core/api/apiClient.js'

export function getViewingAvailability(propertyId) {
  return apiRequest(`/api/properties/${encodeURIComponent(propertyId)}/viewing-availability`, {
    errorMessage: 'Unable to load viewing availability.',
  })
}

export function saveViewingAvailability(propertyId, schedule) {
  return apiRequest(`/api/properties/${encodeURIComponent(propertyId)}/viewing-availability`, {
    method: 'PUT', body: JSON.stringify(schedule),
    errorMessage: 'Unable to save viewing availability.',
  })
}
