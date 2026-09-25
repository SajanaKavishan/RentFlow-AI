import { apiRequest } from '../../core/api/apiClient.js'

function invalidResponse() {
  throw new TypeError('The service returned an invalid staff provisioning response.')
}

function parsePendingTechnician(response) {
  if (!response || typeof response.id !== 'string'
    || typeof response.fullName !== 'string'
    || typeof response.email !== 'string'
    || typeof response.phoneNumber !== 'string'
    || response.role !== 'MaintenanceTechnician'
    || response.isActive !== false
    || typeof response.passwordSetupToken !== 'string'
    || response.passwordSetupToken.length < 32
    || typeof response.passwordSetupExpiresAt !== 'string'
    || Number.isNaN(Date.parse(response.passwordSetupExpiresAt))) invalidResponse()
  return response
}

export async function createMaintenanceTechnician(details) {
  return parsePendingTechnician(await apiRequest(
    '/api/admin/maintenance-technicians',
    {
      method: 'POST',
      body: JSON.stringify(details),
      errorMessage: 'The pending Technician account could not be created.',
    },
  ))
}

export async function activateMaintenanceTechnician(details) {
  return apiRequest('/api/auth/maintenance-technicians/activate', {
    method: 'POST',
    body: JSON.stringify(details),
    authenticated: false,
    handleUnauthorized: false,
    parse: 'none',
    errorMessage: 'Password setup could not be completed.',
  })
}
