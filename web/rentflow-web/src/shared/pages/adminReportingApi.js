import { ApiError, apiRequest } from '../../core/api/apiClient.js'

const count = (value) => Number.isInteger(value) && value >= 0
const date = (value) => typeof value === 'string' && Number.isFinite(Date.parse(value))
const validators = {
  summary: (data) => data && count(data.propertyCount) && count(data.activeApplicationCount) &&
    Number.isFinite(data.monthlyVolume) && data.monthlyVolume >= 0 && /^\d{4}-(0[1-9]|1[0-2])$/.test(data.month),
  activity: (data) => Array.isArray(data) && data.every((item) => typeof item?.kind === 'string' && typeof item.description === 'string' && date(item.occurredAt)),
  workflows: (data) => Array.isArray(data) && data.length === 3 && data.every((item) => typeof item?.name === 'string' &&
    ['total', 'pending', 'running', 'awaitingReview', 'completed', 'failed'].every((key) => count(item[key])) &&
    item.total === item.pending + item.running + item.awaitingReview + item.completed + item.failed),
  health: (data) => date(data?.checkedAt) && Array.isArray(data.services) && data.services.length > 0 &&
    data.services.every((item) => typeof item?.name === 'string' && ['available', 'unavailable'].includes(item.status) && typeof item.detail === 'string'),
}

export async function getAdminReport(kind, signal) {
  if (!validators[kind]) throw new TypeError('Unsupported Admin report')
  const data = await apiRequest(`/api/admin/dashboard/${kind}`, { signal, cache: 'no-store', errorMessage: 'Admin reporting could not be loaded.' })
  if (!validators[kind](data)) throw new ApiError('The reporting service returned an invalid report.')
  return data
}

export async function getAdminActivityPage(page, signal) {
  const data = await apiRequest(`/api/admin/dashboard/activity?page=${page}&pageSize=50`, {
    signal, cache: 'no-store', errorMessage: 'Platform activity could not be loaded.',
  })
  if (!validators.activity(data)) throw new ApiError('The reporting service returned an invalid report.')
  return data
}
