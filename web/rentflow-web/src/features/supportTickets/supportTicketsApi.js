import { apiRequest } from '../../core/api/apiClient.js'

export const SUPPORT_CATEGORIES = Object.freeze([
  { value: 'TechnicalIssue', label: 'Technical issue' },
  { value: 'AccountLogin', label: 'Account or login' },
  { value: 'PropertyApplication', label: 'Property or application' },
  { value: 'Payment', label: 'Payment' },
  { value: 'Other', label: 'Other' },
])

const categoryValues = new Set(SUPPORT_CATEGORIES.map(({ value }) => value))

function invalidResponse() {
  throw new TypeError('The service returned an invalid support ticket response.')
}

function parseTicket(ticket) {
  if (!ticket || typeof ticket.id !== 'string'
    || !categoryValues.has(ticket.category)
    || typeof ticket.subject !== 'string'
    || typeof ticket.message !== 'string'
    || typeof ticket.status !== 'string'
    || typeof ticket.createdAt !== 'string'
    || typeof ticket.updatedAt !== 'string'
    || Number.isNaN(Date.parse(ticket.createdAt))
    || Number.isNaN(Date.parse(ticket.updatedAt))) invalidResponse()
  return ticket
}

export async function createSupportTicket({ category, subject, message }) {
  const response = await apiRequest('/api/support-tickets', {
    method: 'POST',
    body: JSON.stringify({ category, subject, message }),
    errorMessage: 'Your support request could not be submitted.',
  })
  return parseTicket(response)
}

export async function getMySupportTickets() {
  const response = await apiRequest('/api/support-tickets/mine', {
    errorMessage: 'Your support requests could not be loaded.',
  })
  if (!Array.isArray(response)) invalidResponse()
  return response.map(parseTicket)
}
