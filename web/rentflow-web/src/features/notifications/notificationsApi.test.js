import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { getNotifications, getUnreadCount, markNotificationRead } from './notificationsApi.js'

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const item = { id: '11111111-1111-1111-1111-111111111111', title: 'Viewing confirmed', message: 'Your viewing was confirmed.', createdAt: '2026-09-20T10:00:00Z', isRead: false }
const page = { items: [item], pagination: { page: 2, pageSize: 20, totalCount: 21, totalPages: 2, hasNextPage: false, hasPreviousPage: true } }

beforeEach(() => { tokenStorage.setToken('session-token'); vi.stubGlobal('fetch', vi.fn()) })
afterEach(() => { tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('notifications API', () => {
  it('uses the authenticated user scope and the backend pagination contract', async () => {
    fetch.mockResolvedValueOnce(json(page)).mockResolvedValueOnce(json({ unreadCount: 3 }))
    expect(await getNotifications(2)).toEqual(page)
    expect(await getUnreadCount()).toBe(3)
    expect(fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost').pathname + new URL(url, 'http://localhost').search)).toEqual([
      '/api/notifications?page=2&pageSize=20', '/api/notifications/unread-count',
    ])
    for (const [url, options] of fetch.mock.calls) {
      expect(options.headers.Authorization).toBe('Bearer session-token')
      expect(url).not.toContain('userId')
      expect(url).not.toContain('recipientId')
    }
  })

  it('PATCHes only the selected notification and returns the confirmed read state', async () => {
    fetch.mockResolvedValue(json({ ...item, isRead: true, readAt: '2026-09-22T10:00:00Z' }))
    expect((await markNotificationRead(item.id)).isRead).toBe(true)
    const [url, options] = fetch.mock.calls[0]
    expect(new URL(url, 'http://localhost').pathname).toBe(`/api/notifications/${item.id}/read`)
    expect(options.method).toBe('PATCH')
    expect(options.headers.Authorization).toBe('Bearer session-token')
    expect(options.body).toBeUndefined()
  })

  it('rejects malformed count, page and read responses', async () => {
    fetch.mockResolvedValueOnce(json({ unreadCount: '3' })).mockResolvedValueOnce(json({ items: [] })).mockResolvedValueOnce(json(item))
    await expect(getUnreadCount()).rejects.toThrow('invalid notifications response')
    await expect(getNotifications()).rejects.toThrow('invalid notifications response')
    await expect(markNotificationRead(item.id)).rejects.toThrow('invalid notifications response')
  })
})
