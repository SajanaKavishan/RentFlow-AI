import { apiRequest } from '../../../core/api/apiClient.js'

const leasePath = (leaseId) => `/api/rent-schedules/lease/${encodeURIComponent(leaseId)}`

export function getRentScheduleByLease(leaseId) {
  return apiRequest(leasePath(leaseId), { errorMessage: 'Unable to load the rent schedule.' })
}

export function generateRentSchedule(leaseId) {
  return apiRequest(`${leasePath(leaseId)}/generate`, {
    method: 'POST',
    errorMessage: 'Unable to generate the rent schedule.',
  })
}

export function getRentScheduleItem(id) {
  return apiRequest(`/api/rent-schedules/${encodeURIComponent(id)}`, {
    errorMessage: 'Unable to load the rent schedule item.',
  })
}
