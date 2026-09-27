import { apiRequest } from '../../../core/api/apiClient.js'

export const getMyOffers = () => apiRequest('/api/rental-offers/mine', { errorMessage: 'Unable to load your rental offers.' })
export const getOffer = (id) => apiRequest(`/api/rental-offers/${encodeURIComponent(id)}`, { errorMessage: 'Unable to load the rental offer.' })
export const respondToOffer = (id, action) => apiRequest(`/api/rental-offers/${encodeURIComponent(id)}/${action}`, {
  method: 'PATCH', errorMessage: 'Unable to update the rental offer.',
})

export const getMyLeases = () => apiRequest('/api/lease-agreements/mine', { errorMessage: 'Unable to load your leases.' })
export const getLease = (id) => apiRequest(`/api/lease-agreements/${encodeURIComponent(id)}`, { errorMessage: 'Unable to load the lease.' })

export const getScheduleByLease = (id) => apiRequest(`/api/rent-schedules/lease/${encodeURIComponent(id)}`, { errorMessage: 'Unable to load the rent schedule.' })
export const getScheduleItem = (id) => apiRequest(`/api/rent-schedules/${encodeURIComponent(id)}`, { errorMessage: 'Unable to load the schedule item.' })

export const getMyPayments = () => apiRequest('/api/payments/mine', { errorMessage: 'Unable to load your payments.' })
export const getPayment = (id) => apiRequest(`/api/payments/${encodeURIComponent(id)}`, { errorMessage: 'Unable to load the payment.' })
export const createPayment = (payload) => apiRequest('/api/payments', {
  method: 'POST', body: JSON.stringify(payload), errorMessage: 'Unable to create the payment.',
})
