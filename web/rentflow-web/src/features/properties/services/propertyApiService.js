import { apiRequest } from '../../../core/api/apiClient.js'

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

export function matchProperties(preferences) {
  return apiRequest('/api/properties/match', {
    method: 'POST',
    body: JSON.stringify(preferences),
    errorMessage: 'Unable to generate property recommendations.',
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
