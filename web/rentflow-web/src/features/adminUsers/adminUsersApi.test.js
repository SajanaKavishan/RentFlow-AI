import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import {
  ADMIN_USER_DISTRIBUTION_ROLES,
  getAdminUserRoleTotals,
  getAdminUsers,
  getAdminUserTotal,
  getAdminUserDetails,
  deactivateAdminUser,
} from './adminUsersApi.js'

const user = {
  id: '11111111-1111-4111-8111-111111111111',
  fullName: 'Sam Admin',
  email: 'sam@example.com',
  role: 'Admin',
  isActive: true,
  createdAt: '2026-09-24T00:00:00Z',
}
const page = {
  items: [user],
  pagination: {
    page: 2, pageSize: 8, totalCount: 9, totalPages: 2,
    hasNextPage: false, hasPreviousPage: true,
  },
}
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
})

it('loads only display fields from the authenticated profile endpoint', async () => {
  fetch.mockResolvedValue(json({ ...user, phoneNumber: '+94770000000', passwordHash: 'must-not-leak', tokenVersion: 5 }))
  const details = await getAdminUserDetails(user.id)
  expect(details.phoneNumber).toBe('+94770000000')
  expect(details).not.toHaveProperty('passwordHash')
  expect(details).not.toHaveProperty('tokenVersion')
  expect(fetch.mock.calls[0][0]).toContain(`/api/admin/users/${user.id}`)
  expect(fetch.mock.calls[0][1].headers.Authorization).toBe('Bearer admin-token')
})

it('requires the deactivation response to identify the target and report Inactive', async () => {
  fetch.mockResolvedValueOnce(json({ ...user, phoneNumber: '', isActive: false }))
  expect((await deactivateAdminUser(user.id)).isActive).toBe(false)
  expect(fetch.mock.calls[0][1].method).toBe('PATCH')
  fetch.mockResolvedValueOnce(json({ ...user, phoneNumber: '', isActive: true }))
  await expect(deactivateAdminUser(user.id)).rejects.toThrow('invalid user directory response')
})

beforeEach(() => {
  tokenStorage.setToken('admin-token')
  vi.stubGlobal('fetch', vi.fn())
})
afterEach(() => {
  tokenStorage.clearToken()
  vi.unstubAllGlobals()
})

describe('Admin user directory API', () => {
  it('uses Admin authentication and the exact server-side filter parameters', async () => {
    fetch.mockResolvedValue(json(page))
    const controller = new AbortController()

    await expect(getAdminUsers({
      page: 2,
      pageSize: 8,
      search: '  sam@example.com  ',
      role: 'Admin',
      isActive: true,
      signal: controller.signal,
    })).resolves.toEqual(page)

    const [url, options] = fetch.mock.calls[0]
    const parsedUrl = new URL(url, 'http://localhost')
    expect(parsedUrl.pathname).toBe('/api/admin/users')
    expect(Object.fromEntries(parsedUrl.searchParams)).toEqual({
      page: '2',
      pageSize: '8',
      search: 'sam@example.com',
      role: 'Admin',
      isActive: 'true',
    })
    expect(options.headers.Authorization).toBe('Bearer admin-token')
    expect(options.signal).toBe(controller.signal)
  })

  it('omits optional filters when All is selected', async () => {
    fetch.mockResolvedValue(json({
      items: [],
      pagination: {
        page: 1, pageSize: 8, totalCount: 0, totalPages: 0,
        hasNextPage: false, hasPreviousPage: false,
      },
    }))

    await getAdminUsers()

    const url = new URL(fetch.mock.calls[0][0], 'http://localhost')
    expect(url.search).toBe('?page=1&pageSize=8')
  })

  it('reads the total user count from an unfiltered one-row directory page', async () => {
    fetch.mockResolvedValue(json({
      items: [user],
      pagination: {
        page: 1, pageSize: 1, totalCount: 47, totalPages: 47,
        hasNextPage: true, hasPreviousPage: false,
      },
    }))

    await expect(getAdminUserTotal()).resolves.toBe(47)

    const [requestUrl, options] = fetch.mock.calls[0]
    const url = new URL(requestUrl, 'http://localhost')
    expect(url.pathname).toBe('/api/admin/users')
    expect(url.search).toBe('?page=1&pageSize=1')
    expect(options.headers.Authorization).toBe('Bearer admin-token')
  })

  it('reads each role total from authenticated minimal filtered pages', async () => {
    const totals = { Tenant: 12, Landlord: 5, MaintenanceTechnician: 3, Admin: 2 }
    fetch.mockImplementation((requestUrl) => {
      const url = new URL(requestUrl, 'http://localhost')
      const role = url.searchParams.get('role')
      return Promise.resolve(json({
        items: [{ ...user, role }],
        pagination: {
          page: 1, pageSize: 1, totalCount: totals[role], totalPages: totals[role],
          hasNextPage: totals[role] > 1, hasPreviousPage: false,
        },
      }))
    })

    await expect(getAdminUserRoleTotals()).resolves.toEqual(totals)
    expect(fetch).toHaveBeenCalledTimes(4)

    const requestedRoles = fetch.mock.calls.map(([requestUrl, options]) => {
      const url = new URL(requestUrl, 'http://localhost')
      expect(url.pathname).toBe('/api/admin/users')
      expect(Object.fromEntries(url.searchParams)).toEqual({
        page: '1', pageSize: '1', role: url.searchParams.get('role'),
      })
      expect(url.searchParams.has('isActive')).toBe(false)
      expect(options.headers.Authorization).toBe('Bearer admin-token')
      return url.searchParams.get('role')
    })
    expect(requestedRoles).toEqual(ADMIN_USER_DISTRIBUTION_ROLES)
  })

  it('keeps unexpected authentication fields out of the parsed directory data', async () => {
    fetch.mockResolvedValue(json({
      items: [{ ...user, passwordHash: 'secret-hash', passwordSetupToken: 'secret-token' }],
      pagination: {
        page: 1, pageSize: 8, totalCount: 1, totalPages: 1,
        hasNextPage: false, hasPreviousPage: false,
      },
    }))

    const result = await getAdminUsers()

    expect(result.items[0]).toEqual(user)
    expect(result.items[0]).not.toHaveProperty('passwordHash')
    expect(result.items[0]).not.toHaveProperty('passwordSetupToken')
  })

  it.each([
    [{ ...page, items: [{ ...user, role: 'Owner' }] }],
    [{ ...page, items: [{ ...user, createdAt: 'not-a-date' }] }],
    [{ ...page, pagination: { ...page.pagination, totalCount: 99 } }],
    [{ ...page, pagination: { ...page.pagination, page: 1 } }],
    [{ ...page, items: [user, user] }],
  ])('rejects malformed or misleading directory responses', async (response) => {
    fetch.mockResolvedValue(json(response))

    await expect(getAdminUsers({ page: 2 })).rejects.toThrow('invalid user directory response')
  })
})
