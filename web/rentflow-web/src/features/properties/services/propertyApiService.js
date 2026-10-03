import { apiRequest } from '../../../core/api/apiClient.js'
import { API_BASE_URL } from '../../../core/api/apiConfig.js'

export function getProperties(filters = {}) {
  const params = new URLSearchParams()

  Object.entries(filters).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') {
      params.set(key, value)
    }
  })

  const query = params.toString()

  return apiRequest(`/api/properties${query ? `?${query}` : ''}`, {
    authenticated: false,
    errorMessage: 'Unable to load properties.',
  })
}

export function getMyProperties() {
  return apiRequest('/api/properties/mine', {
    errorMessage: 'Unable to load your properties.',
  })
}

export function getProperty(propertyId) {
  return apiRequest(`/api/properties/${propertyId}`, {
    authenticated: false,
    errorMessage: 'Unable to load the property.',
  })
}

export function createProperty(property) {
  return apiRequest('/api/properties', {
    method: 'POST',
    body: JSON.stringify(property),
    errorMessage: 'Unable to create the property.',
  })
}

export function updateProperty(propertyId, property) {
  return apiRequest(`/api/properties/${propertyId}`, {
    method: 'PUT',
    body: JSON.stringify(property),
    errorMessage: 'Unable to update the property.',
  })
}

export function deleteProperty(propertyId) {
  return apiRequest(`/api/properties/${propertyId}`, {
    method: 'DELETE',
    parse: 'none',
    errorMessage: 'Unable to delete the property.',
  })
}

export function getPropertyImages(propertyId) {
  return apiRequest(`/api/properties/${propertyId}/images`, {
    authenticated: false,
    errorMessage: 'Unable to load property images.',
  })
}

export function getPropertyImageUrl(propertyId, imageId) {
  return apiRequest(
    `/api/properties/${propertyId}/images/${imageId}/url`,
    {
      authenticated: false,
      errorMessage: 'Unable to load the property image.',
    },
  )
}

export function uploadPropertyImage(propertyId, file) {
  const formData = new FormData()
  formData.append('file', file)

  return apiRequest(`/api/properties/${propertyId}/images`, {
    method: 'POST',
    body: formData,
    errorMessage: 'Unable to upload the property image.',
  })
}

export async function uploadPropertyImages(propertyId, files) {
  const results = []

  for (const file of files) {
    results.push(
      await uploadPropertyImage(propertyId, file),
    )
  }

  return results
}

export function deletePropertyImage(propertyId, imageId) {
  return apiRequest(
    `/api/properties/${propertyId}/images/${imageId}`,
    {
      method: 'DELETE',
      parse: 'none',
      errorMessage: 'Unable to delete the property image.',
    },
  )
}

export function updatePropertyListing(propertyId, property) {
  return apiRequest(`/api/properties/${propertyId}/listing`, {
    method: 'PUT',
    body: JSON.stringify(property),
    errorMessage: 'Unable to update the property listing.',
  })
}

export function getPublicLandlordSummary(propertyId) {
  return apiRequest(`/api/properties/${encodeURIComponent(propertyId)}/landlord-summary`, {
    authenticated: false,
    errorMessage: 'Landlord details are unavailable.',
  })
}

export function getPublicLandlordImageUrl(propertyId) {
  return `${API_BASE_URL}/api/properties/${encodeURIComponent(propertyId)}/landlord-summary/image`
}

export function setPrimaryPropertyImage(propertyId, imageId) {
  return apiRequest(`/api/properties/${propertyId}/images/${imageId}/primary`, {
    method: 'PUT',
    errorMessage: 'Unable to set the cover photo.',
  })
}

export function reorderPropertyImages(propertyId, imageIds) {
  return apiRequest(`/api/properties/${propertyId}/images/order`, {
    method: 'PUT',
    body: JSON.stringify({ imageIds }),
    errorMessage: 'Unable to reorder property photos.',
  })
}

export function getMatchPreferences() {
  return apiRequest('/api/tenant/property-preferences', {
    errorMessage: "We couldn't load your match preferences.",
  })
}

export function saveMatchPreferences(preferences) {
  return apiRequest('/api/tenant/property-preferences', {
    method: 'PUT',
    body: JSON.stringify(preferences),
    errorMessage: "We couldn't save your match preferences.",
  })
}

export function resetMatchPreferences() {
  return apiRequest('/api/tenant/property-preferences', {
    method: 'DELETE',
    parse: 'none',
    errorMessage: "We couldn't reset your match preferences.",
  })
}

export function getSavedPropertyMatches() {
  return apiRequest('/api/properties/matches', {
    errorMessage: "We couldn't calculate your matches.",
  })
}

export function getPropertyFavorites() {
  return apiRequest('/api/tenant/property-favorites', {
    errorMessage: "We couldn't load your liked properties.",
  })
}

export function addPropertyFavorite(propertyId) {
  return apiRequest(`/api/tenant/property-favorites/${propertyId}`, {
    method: 'PUT',
    parse: 'none',
    errorMessage: "We couldn't add this property to your liked properties.",
  })
}

export function removePropertyFavorite(propertyId) {
  return apiRequest(`/api/tenant/property-favorites/${propertyId}`, {
    method: 'DELETE',
    parse: 'none',
    errorMessage: "We couldn't remove this property from your liked properties.",
  })
}
