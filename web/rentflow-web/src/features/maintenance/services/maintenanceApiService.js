import { ApiError, apiRequest } from '../../../core/api/apiClient.js'
import {
  encodeMaintenanceRequest,
  normalizeMaintenanceCoordinationWorkflow,
  normalizeMaintenanceRequest,
} from './maintenanceEnums.js'

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
    body: JSON.stringify(encodeMaintenanceRequest(payload)),
  }).then(normalizeMaintenanceRequest)
}

export function getMaintenanceRequestById(id) {
  return request(maintenanceRequestPath(id)).then(normalizeMaintenanceRequest)
}

export function getTenantMaintenanceRequests(tenantId) {
  return request(`/api/maintenance-requests/tenant/${encodeURIComponent(tenantId)}`)
    .then((items) => items.map(normalizeMaintenanceRequest))
}

export function getTechnicianMaintenanceRequests(technicianId) {
  return request(`/api/maintenance-requests/technician/${encodeURIComponent(technicianId)}`)
    .then((items) => items.map(normalizeMaintenanceRequest))
}

export function getPropertyMaintenanceRequests(propertyId) {
  return request(`/api/maintenance-requests/property/${encodeURIComponent(propertyId)}`)
    .then((items) => items.map(normalizeMaintenanceRequest))
}

export function getTenantProperties() {
  return request('/api/properties/tenant/mine')
}

export function getLandlordMaintenanceProperties() {
  return request('/api/properties/mine')
}

export function getMaintenanceTechnicians() {
  return request('/api/maintenance-requests/technicians')
}

export function getMaintenanceHistory(id) {
  return request(maintenanceRequestPath(id, 'history'))
}

export function triageMaintenanceRequest(id, payload) {
  const encoded = encodeMaintenanceRequest(payload)
  return request(maintenanceRequestPath(id, 'triage'), {
    method: 'PATCH',
    body: JSON.stringify({
      category: encoded.category,
      priority: encoded.priority,
      triageNotes: String(payload.triageNotes ?? '').trim() || null,
    }),
  }).then(normalizeMaintenanceRequest)
}

export function assignMaintenanceTechnician(id, payload) {
  return request(maintenanceRequestPath(id, 'assign-technician'), {
    method: 'PATCH',
    body: JSON.stringify({
      technicianId: payload.technicianId,
      assignmentNotes: String(payload.assignmentNotes ?? '').trim() || null,
    }),
  }).then(normalizeMaintenanceRequest)
}

export function markMaintenanceEstimatePending(id) {
  return request(maintenanceRequestPath(id, 'estimate-pending'), {
    method: 'PATCH',
  }).then(normalizeMaintenanceRequest)
}

export function startWork(id) {
  return request(maintenanceRequestPath(id, 'start-work'), {
    method: 'PATCH',
  }).then(normalizeMaintenanceRequest)
}

export function completeWork(id) {
  return request(maintenanceRequestPath(id, 'complete-work'), {
    method: 'PATCH',
  }).then(normalizeMaintenanceRequest)
}

export function getEstimates(id) {
  return request(maintenanceRequestPath(id, 'estimates'))
}

export function getLatestEstimate(id) {
  return request(maintenanceRequestPath(id, 'estimates/latest'))
}

export function createRepairEstimate(id, payload) {
  return request(maintenanceRequestPath(id, 'estimates'), {
    method: 'POST',
    body: JSON.stringify({
      laborCost: Number(payload.laborCost),
      partsCost: Number(payload.partsCost),
      additionalCost: Number(payload.additionalCost),
      notes: String(payload.notes ?? '').trim() || null,
    }),
  })
}

export function submitEstimateForReview(id, estimateId) {
  return request(`${maintenanceRequestPath(id, 'estimates')}/${encodeURIComponent(estimateId)}/submit-for-review`, {
    method: 'PATCH',
  }).then(normalizeMaintenanceRequest)
}

export function reviewRepairEstimate(id, estimateId, action, reviewNotes = '') {
  if (!['approve', 'reject', 'request-revision'].includes(action)) {
    throw new TypeError(`Invalid estimate review action: ${action}`)
  }
  return request(`${maintenanceRequestPath(id, 'estimates')}/${encodeURIComponent(estimateId)}/${action}`, {
    method: 'PATCH',
    body: JSON.stringify({ reviewNotes: String(reviewNotes ?? '').trim() || null }),
  })
}

export function startCoordinationWorkflow(id) {
  return request(maintenanceRequestPath(id, 'coordination-workflows'), {
    method: 'POST',
  }).then(normalizeMaintenanceCoordinationWorkflow)
}

export function getCoordinationWorkflow(id, workflowId) {
  return request(coordinationWorkflowPath(id, workflowId))
    .then(normalizeMaintenanceCoordinationWorkflow)
}

export function approveCoordinationWorkflow(id, workflowId, decisionNotes = '') {
  return request(coordinationWorkflowPath(id, workflowId, 'approve'), {
    method: 'PATCH',
    body: JSON.stringify({ decisionNotes: String(decisionNotes ?? '').trim() || null }),
  }).then(normalizeMaintenanceCoordinationWorkflow)
}

export function rejectCoordinationWorkflow(id, workflowId, decisionNotes = '') {
  return request(coordinationWorkflowPath(id, workflowId, 'reject'), {
    method: 'PATCH',
    body: JSON.stringify({ decisionNotes: String(decisionNotes ?? '').trim() || null }),
  }).then(normalizeMaintenanceCoordinationWorkflow)
}

function tenantActorQuery(tenantId) {
  return tenantId == null ? '' : `?tenantId=${encodeURIComponent(tenantId)}`
}

function attachmentPath(id, attachmentId) {
  const base = maintenanceRequestPath(id, 'attachments')
  return attachmentId == null ? base : `${base}/${encodeURIComponent(attachmentId)}`
}

export function getMaintenanceAttachments(id, tenantId) {
  return request(`${attachmentPath(id)}${tenantActorQuery(tenantId)}`)
}

export function uploadMaintenanceAttachment(id, tenantId, file, attachmentType = '') {
  const formData = new FormData()
  formData.append('file', file)
  if (attachmentType.trim()) formData.append('attachmentType', attachmentType.trim())
  return request(`${attachmentPath(id)}${tenantActorQuery(tenantId)}`, {
    method: 'POST',
    body: formData,
  })
}

export function getMaintenanceAttachmentDownload(id, attachmentId, tenantId) {
  return request(`${attachmentPath(id, attachmentId)}${tenantActorQuery(tenantId)}`, {
    parse: 'response',
    redirect: 'follow',
  })
}

export function deleteMaintenanceAttachment(id, attachmentId, tenantId) {
  return request(`${attachmentPath(id, attachmentId)}${tenantActorQuery(tenantId)}`, {
    method: 'DELETE',
    parse: 'none',
  })
}
