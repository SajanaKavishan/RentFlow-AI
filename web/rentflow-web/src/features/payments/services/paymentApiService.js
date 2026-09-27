import { apiRequest } from '../../../core/api/apiClient.js'

const paymentPath = (id) => `/api/payments/${encodeURIComponent(id)}`

export function getLandlordPayments() {
  return apiRequest('/api/payments/landlord', { errorMessage: 'Unable to load payments.' })
}

export function getPayment(id) {
  return apiRequest(paymentPath(id), { errorMessage: 'Unable to load payment details.' })
}

export function changePaymentStatus(id, action) {
  if (!['complete', 'fail'].includes(action)) throw new TypeError('Unsupported payment action.')
  return apiRequest(`${paymentPath(id)}/${action}`, {
    method: 'PATCH',
    errorMessage: 'Unable to update the payment.',
  })
}
