import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { createSupportTicket, getMySupportTickets } from './supportTicketsApi.js'

const ticket = {
  id: '11111111-1111-1111-1111-111111111111',
  category: 'TechnicalIssue',
  subject: 'Page will not load',
  message: 'The profile page remains in a loading state.',
  status: 'Open',
  createdAt: '2026-09-26T10:00:00Z',
  updatedAt: '2026-09-26T10:00:00Z',
}
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'Content-Type': 'application/json' },
})

beforeEach(() => {
  tokenStorage.setToken('support-session-token')
  vi.stubGlobal('fetch', vi.fn())
})
afterEach(() => { tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('support tickets API', () => {
  it('creates and lists tickets through authenticated user-scoped endpoints', async () => {
    fetch.mockResolvedValueOnce(json(ticket, 201)).mockResolvedValueOnce(json([ticket]))

    expect(await createSupportTicket({
      category: ticket.category,
      subject: ticket.subject,
      message: ticket.message,
    })).toEqual(ticket)
    expect(await getMySupportTickets()).toEqual([ticket])

    const [createUrl, createOptions] = fetch.mock.calls[0]
    expect(new URL(createUrl, 'http://localhost').pathname).toBe('/api/support-tickets')
    expect(createOptions.method).toBe('POST')
    expect(createOptions.headers.Authorization).toBe('Bearer support-session-token')
    expect(JSON.parse(createOptions.body)).toEqual({
      category: ticket.category,
      subject: ticket.subject,
      message: ticket.message,
    })
    expect(createOptions.body).not.toContain('userId')
    expect(createOptions.body).not.toContain('role')

    const [listUrl, listOptions] = fetch.mock.calls[1]
    expect(new URL(listUrl, 'http://localhost').pathname).toBe('/api/support-tickets/mine')
    expect(listOptions.headers.Authorization).toBe('Bearer support-session-token')
  })

  it('rejects malformed create and list responses', async () => {
    fetch.mockResolvedValueOnce(json({ ...ticket, status: null }, 201))
      .mockResolvedValueOnce(json({ items: [ticket] }))

    await expect(createSupportTicket({
      category: ticket.category,
      subject: ticket.subject,
      message: ticket.message,
    })).rejects.toThrow('invalid support ticket response')
    await expect(getMySupportTickets()).rejects.toThrow('invalid support ticket response')
  })
})
