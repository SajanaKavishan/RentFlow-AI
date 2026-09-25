import { apiRequest } from '../../core/api/apiClient.js'

function parsePreferences(response) {
  if (typeof response?.viewingUpdatesEnabled !== 'boolean'
    || typeof response?.rentalApplicationUpdatesEnabled !== 'boolean'
    || response?.accountSecurityUpdatesEnabled !== true) {
    throw new TypeError('The service returned an invalid notification preferences response.')
  }
  return response
}

export async function getNotificationPreferences() {
  return parsePreferences(await apiRequest('/api/notification-preferences', {
    errorMessage: 'Notification preferences could not be loaded.',
  }))
}

export async function updateNotificationPreferences(preferences) {
  return parsePreferences(await apiRequest('/api/notification-preferences', {
    method: 'PUT',
    body: JSON.stringify({
      viewingUpdatesEnabled: preferences.viewingUpdatesEnabled,
      rentalApplicationUpdatesEnabled: preferences.rentalApplicationUpdatesEnabled,
      accountSecurityUpdatesEnabled: true,
    }),
    errorMessage: 'Notification preferences could not be saved.',
  }))
}
