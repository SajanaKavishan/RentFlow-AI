import { apiRequest } from '../../core/api/apiClient.js'

export const ADMIN_USER_ROLES = Object.freeze([
  'Tenant',
  'Landlord',
  'MaintenanceTechnician',
  'Admin',
])

export const ADMIN_USERS_PAGE_SIZE = 8

export const ADMIN_USER_DISTRIBUTION_ROLES = Object.freeze([
  'Tenant',
  'Landlord',
  'MaintenanceTechnician',
  'Admin',
])

const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function invalidResponse() {
  throw new TypeError('The service returned an invalid user directory response.')
}

function parseUser(item) {
  if (!item || typeof item.id !== 'string' || !idPattern.test(item.id)
    || typeof item.fullName !== 'string' || !item.fullName.trim()
    || typeof item.email !== 'string' || !item.email.trim()
    || !ADMIN_USER_ROLES.includes(item.role)
    || typeof item.isActive !== 'boolean'
    || typeof item.createdAt !== 'string'
    || Number.isNaN(Date.parse(item.createdAt))) invalidResponse()
  return {
    id: item.id,
    fullName: item.fullName,
    email: item.email,
    role: item.role,
    isActive: item.isActive,
    createdAt: item.createdAt,
  }
}

function parsePage(response, requestedPage, requestedPageSize) {
  const pagination = response?.pagination
  if (!Array.isArray(response?.items) || !pagination
    || !Number.isInteger(pagination.page) || pagination.page !== requestedPage
    || !Number.isInteger(pagination.pageSize) || pagination.pageSize !== requestedPageSize
    || !Number.isInteger(pagination.totalCount) || pagination.totalCount < 0
    || !Number.isInteger(pagination.totalPages) || pagination.totalPages < 0
    || pagination.totalPages !== Math.ceil(pagination.totalCount / requestedPageSize)
    || typeof pagination.hasNextPage !== 'boolean'
    || pagination.hasNextPage !== (pagination.page < pagination.totalPages)
    || typeof pagination.hasPreviousPage !== 'boolean'
    || pagination.hasPreviousPage !== (pagination.page > 1 && pagination.totalPages > 0)
    || response.items.length > requestedPageSize) invalidResponse()

  const items = response.items.map(parseUser)
  if (new Set(items.map((item) => item.id.toLowerCase())).size !== items.length) invalidResponse()
  return { items, pagination }
}

export async function getAdminUsers({
  page = 1,
  pageSize = ADMIN_USERS_PAGE_SIZE,
  search = '',
  role = '',
  isActive,
  signal,
} = {}) {
  const query = new URLSearchParams({ page: String(page), pageSize: String(pageSize) })
  const trimmedSearch = search.trim()
  if (trimmedSearch) query.set('search', trimmedSearch)
  if (role) query.set('role', role)
  if (typeof isActive === 'boolean') query.set('isActive', String(isActive))

  const response = await apiRequest(`/api/admin/users?${query}`, {
    signal,
    errorMessage: 'The user directory could not be loaded.',
    networkErrorMessage: 'Unable to connect to the user directory. Please try again.',
  })
  return parsePage(response, page, pageSize)
}

export async function getAdminUserTotal({ signal } = {}) {
  const { pagination } = await getAdminUsers({ page: 1, pageSize: 1, signal })
  return pagination.totalCount
}

export async function getAdminUserRoleTotals({ signal } = {}) {
  const totals = await Promise.all(ADMIN_USER_DISTRIBUTION_ROLES.map(async (role) => {
    const { pagination } = await getAdminUsers({ page: 1, pageSize: 1, role, signal })
    return [role, pagination.totalCount]
  }))
  return Object.fromEntries(totals)
}
