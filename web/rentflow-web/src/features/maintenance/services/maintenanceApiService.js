import { ApiError, apiRequest } from '../../../core/api/apiClient.js'

export class MaintenanceApiError extends ApiError {
  constructor(message, statusCode = null) {
    super(message)
    this.name = 'MaintenanceApiError'
    this.statusCode = statusCode
  }
}

async function request(path, options = {}) {
  try {
    return await apiRequest(path, {
      ...options,
      errorMessage: 'The maintenance request failed. Please try again.',
      networkErrorMessage: 'Unable to connect to the maintenance service. Please try again.',
    })
  } catch (error) {
    if (error instanceof ApiError) throw new MaintenanceApiError(error.message, error.statusCode)
    throw error
  }
}

function maintenanceRequestPath(id, action = '') {
  const encodedId = encodeURIComponent(id)
  return `/api/maintenance-requests/${encodedId}${action ? `/${action}` : ''}`
}

function coordinationWorkflowPath(id, workflowId, action = '') {
  const base = `${maintenanceRequestPath(id, 'coordination-workflows')}/${encodeURIComponent(workflowId)}`
  return action ? `${base}/${action}` : base
}

export function createMaintenanceRequest(tenantId, payload) {
  const query = tenantId == null ? '' : `?tenantId=${encodeURIComponent(tenantId)}`
  return request(`/api/maintenance-requests${query}`, {
    method: 'POST',
    body: JSON.stringify(payload),
  })
}

export function getMaintenanceRequestById(id) {
  return request(maintenanceRequestPath(id))
}

export function getTenantMaintenanceRequests(tenantId) {
  return request(`/api/maintenance-requests/tenant/${encodeURIComponent(tenantId)}`)
}

export function getPropertyMaintenanceRequests(propertyId) {
  return request(`/api/maintenance-requests/property/${encodeURIComponent(propertyId)}`)
}

export function getMaintenanceHistory(id) {
  return request(maintenanceRequestPath(id, 'history'))
}

export function startWork(id) {
  return request(maintenanceRequestPath(id, 'start-work'), {
    method: 'PATCH',
  })
}

export function completeWork(id) {
  return request(maintenanceRequestPath(id, 'complete-work'), {
    method: 'PATCH',
  })
}

export function getEstimates(id) {
  return request(maintenanceRequestPath(id, 'estimates'))
}

export function getLatestEstimate(id) {
  return request(maintenanceRequestPath(id, 'estimates/latest'))
}

export function getCoordinationWorkflow(id, workflowId) {
  return request(coordinationWorkflowPath(id, workflowId))
}

export function approveCoordinationWorkflow(id, workflowId, decisionNotes = '') {
  return request(coordinationWorkflowPath(id, workflowId, 'approve'), {
    method: 'PATCH',
    body: JSON.stringify({ decisionNotes: String(decisionNotes ?? '').trim() || null }),
  })
}

export function rejectCoordinationWorkflow(id, workflowId, decisionNotes = '') {
  return request(coordinationWorkflowPath(id, workflowId, 'reject'), {
    method: 'PATCH',
    body: JSON.stringify({ decisionNotes: String(decisionNotes ?? '').trim() || null }),
  })
}
