import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import {
  getNotificationPreferences,
  updateNotificationPreferences,
} from './notificationPreferencesApi.js'

const response = {
  viewingUpdatesEnabled: true,
  rentalApplicationUpdatesEnabled: false,
  accountSecurityUpdatesEnabled: true,
}
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'Content-Type': 'application/json' },
})

beforeEach(() => {
  tokenStorage.setToken('preference-token')
  vi.stubGlobal('fetch', vi.fn())
})

afterEach(() => {
  tokenStorage.clearToken()
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('notification preferences API', () => {
  it('loads preferences through the authenticated recipient-scoped endpoint', async () => {
    fetch.mockResolvedValue(json(response))

    await expect(getNotificationPreferences()).resolves.toEqual(response)

    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/notification-preferences'),
      expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer preference-token' }) }),
    )
    expect(fetch.mock.calls[0][1].method).toBeUndefined()
  })

  it('sends only category settings and always keeps account security enabled', async () => {
    fetch.mockResolvedValue(json(response))

    await updateNotificationPreferences({
      viewingUpdatesEnabled: true,
      rentalApplicationUpdatesEnabled: false,
      userId: 'another-user',
      accountSecurityUpdatesEnabled: false,
    })

    const options = fetch.mock.calls[0][1]
    expect(options.method).toBe('PUT')
    expect(JSON.parse(options.body)).toEqual({
      viewingUpdatesEnabled: true,
      rentalApplicationUpdatesEnabled: false,
      accountSecurityUpdatesEnabled: true,
    })
  })

  it('rejects responses that do not confirm the mandatory setting', async () => {
    fetch.mockResolvedValue(json({ ...response, accountSecurityUpdatesEnabled: false }))

    await expect(getNotificationPreferences()).rejects.toThrow('invalid notification preferences response')
  })
})
