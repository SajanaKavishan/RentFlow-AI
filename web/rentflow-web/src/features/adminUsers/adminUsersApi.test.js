import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { getAdminUsers } from './adminUsersApi.js'

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
