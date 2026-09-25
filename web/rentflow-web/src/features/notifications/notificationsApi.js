import { apiRequest } from '../../core/api/apiClient.js'

function invalidResponse() {
  throw new TypeError('The service returned an invalid notifications response.')
}

function parseNotification(item) {
  if (!item || typeof item.id !== 'string' || typeof item.title !== 'string'
    || typeof item.message !== 'string' || typeof item.createdAt !== 'string'
    || typeof item.isRead !== 'boolean' || typeof item.eventType !== 'string'
    || typeof item.relatedResourceType !== 'string'
    || typeof item.relatedResourceId !== 'string') invalidResponse()
  return item
}

export async function getNotifications(page = 1, pageSize = 20) {
  const query = new URLSearchParams({ page: String(page), pageSize: String(pageSize) })
  const response = await apiRequest(`/api/notifications?${query}`, {
    errorMessage: 'Notifications could not be loaded.',
  })
  const pagination = response?.pagination
  if (!Array.isArray(response?.items) || !pagination
    || !Number.isInteger(pagination.page) || !Number.isInteger(pagination.totalPages)
    || !Number.isInteger(pagination.totalCount)
    || typeof pagination.hasNextPage !== 'boolean'
    || typeof pagination.hasPreviousPage !== 'boolean') invalidResponse()
  return { items: response.items.map(parseNotification), pagination }
}

export async function getUnreadCount() {
  const response = await apiRequest('/api/notifications/unread-count', {
    errorMessage: 'Unread notification count could not be loaded.',
  })
  if (!Number.isInteger(response?.unreadCount) || response.unreadCount < 0) invalidResponse()
  return response.unreadCount
}

export async function markNotificationRead(id) {
  const response = await apiRequest(`/api/notifications/${encodeURIComponent(id)}/read`, {
    method: 'PATCH', errorMessage: 'Notification could not be marked as read.',
  })
  const notification = parseNotification(response)
  if (notification.id !== id || !notification.isRead) invalidResponse()
  return notification
}
