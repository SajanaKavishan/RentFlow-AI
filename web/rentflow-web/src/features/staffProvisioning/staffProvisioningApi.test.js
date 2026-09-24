import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import {
  activateMaintenanceTechnician,
  createMaintenanceTechnician,
} from './staffProvisioningApi.js'

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

describe('staff provisioning API', () => {
  it('uses Admin authentication for creation and no JWT for activation', async () => {
    const pending = {
      id: '22222222-2222-2222-2222-222222222222',
      fullName: 'Taylor Technician',
      email: 'tech@example.com',
      phoneNumber: '+94770000001',
      role: 'MaintenanceTechnician',
      isActive: false,
      passwordSetupToken: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG',
      passwordSetupExpiresAt: '2026-09-23T16:00:00Z',
    }
    fetch.mockResolvedValueOnce(json(pending, 201))
      .mockResolvedValueOnce(new Response(null, { status: 204 }))

    await expect(createMaintenanceTechnician({
      fullName: pending.fullName,
      email: pending.email,
      phoneNumber: pending.phoneNumber,
    })).resolves.toEqual(pending)
    await activateMaintenanceTechnician({
      setupToken: pending.passwordSetupToken,
      password: 'Strong1!Password',
      passwordConfirmation: 'Strong1!Password',
    })

    expect(fetch.mock.calls[0][1].headers.Authorization).toBe('Bearer admin-token')
    expect(fetch.mock.calls[1][1].headers.Authorization).toBeUndefined()
  })

  it('rejects a response that could misrepresent role or activation state', async () => {
    fetch.mockResolvedValue(json({
      id: '22222222-2222-2222-2222-222222222222',
      fullName: 'Wrong Role',
      email: 'wrong@example.com',
      phoneNumber: '+94770000001',
      role: 'Admin',
      isActive: true,
      passwordSetupToken: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG',
      passwordSetupExpiresAt: '2026-09-23T16:00:00Z',
    }, 201))

    await expect(createMaintenanceTechnician({
      fullName: 'Wrong Role', email: 'wrong@example.com', phoneNumber: '+94770000001',
    })).rejects.toThrow('invalid staff provisioning response')
  })
})
