import { apiRequest } from '../../core/api/apiClient.js'

export const ADMIN_SUPPORT_PAGE_SIZE = 10
export const SUPPORT_TICKET_STATUSES = Object.freeze(['Open', 'InProgress', 'Resolved'])
export const SUPPORT_TICKET_CATEGORIES = Object.freeze([
  'TechnicalIssue', 'AccountLogin', 'PropertyApplication', 'Payment', 'Other',
])

const statusValues = new Set(SUPPORT_TICKET_STATUSES)
const categoryValues = new Set(SUPPORT_TICKET_CATEGORIES)

function invalidResponse() {
  throw new TypeError('The service returned an invalid Admin support ticket response.')
}

function parseListItem(item) {
  if (!item || typeof item.id !== 'string'
    || !categoryValues.has(item.category)
    || typeof item.subject !== 'string'
    || !statusValues.has(item.status)
    || typeof item.createdAt !== 'string'
    || Number.isNaN(Date.parse(item.createdAt))
    || typeof item.requesterFullName !== 'string'
    || typeof item.requesterEmail !== 'string') invalidResponse()
  return item
}

function parseDetail(item) {
  parseListItem(item)
  if (typeof item.message !== 'string'
    || typeof item.updatedAt !== 'string'
    || Number.isNaN(Date.parse(item.updatedAt))) invalidResponse()
  return item
}

function parsePagination(pagination) {
  if (!pagination
    || !Number.isInteger(pagination.page)
    || !Number.isInteger(pagination.pageSize)
    || !Number.isInteger(pagination.totalCount)
    || !Number.isInteger(pagination.totalPages)
    || typeof pagination.hasNextPage !== 'boolean'
    || typeof pagination.hasPreviousPage !== 'boolean') invalidResponse()
  return pagination
}

export async function getAdminSupportTickets({
  page = 1,
  pageSize = ADMIN_SUPPORT_PAGE_SIZE,
  status = '',
  category = '',
  search = '',
  signal,
} = {}) {
  const query = new URLSearchParams({ page: String(page), pageSize: String(pageSize) })
  if (status) query.set('status', status)
  if (category) query.set('category', category)
  if (search) query.set('search', search)
  const response = await apiRequest(`/api/admin/support-tickets?${query}`, {
    signal,
    errorMessage: 'Support requests could not be loaded.',
  })
  if (!Array.isArray(response?.items)) invalidResponse()
  return {
    items: response.items.map(parseListItem),
    pagination: parsePagination(response.pagination),
  }
}

export async function getAdminSupportTicket(id, { signal } = {}) {
  const response = await apiRequest(`/api/admin/support-tickets/${encodeURIComponent(id)}`, {
    signal,
    errorMessage: 'The support request could not be loaded.',
  })
  return parseDetail(response)
}

export async function updateAdminSupportTicketStatus(id, status) {
  const response = await apiRequest(`/api/admin/support-tickets/${encodeURIComponent(id)}/status`, {
    method: 'PATCH',
    body: JSON.stringify({ status }),
    errorMessage: 'The support request status could not be updated.',
  })
  if (!response || response.id !== id || !statusValues.has(response.status)
    || typeof response.updatedAt !== 'string'
    || Number.isNaN(Date.parse(response.updatedAt))) invalidResponse()
  return response
}
