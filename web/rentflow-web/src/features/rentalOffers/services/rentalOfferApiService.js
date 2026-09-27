import { apiRequest } from '../../../core/api/apiClient.js'

const path = (id) => `/api/rental-offers/${encodeURIComponent(id)}`

export function getLandlordOffers() {
  return apiRequest('/api/rental-offers/landlord', { errorMessage: 'Unable to load rental offers.' })
}

export function createRentalOffer(offer) {
  return apiRequest('/api/rental-offers', {
    method: 'POST',
    body: JSON.stringify(offer),
    errorMessage: 'Unable to create the rental offer.',
  })
}

export function getRentalOffer(id) {
  return apiRequest(path(id), { errorMessage: 'Unable to load the rental offer.' })
}

export function withdrawRentalOffer(id) {
  return apiRequest(`${path(id)}/withdraw`, {
    method: 'PATCH',
    errorMessage: 'Unable to withdraw the rental offer.',
  })
}
