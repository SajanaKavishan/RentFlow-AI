import { apiRequest } from '../../core/api/apiClient.js'

export function getTenantMaintenanceRequests(tenantId) {
  return apiRequest(`/api/maintenance-requests/tenant/${encodeURIComponent(tenantId)}`, {
    errorMessage: 'Unable to load your maintenance requests.',
  })
}
