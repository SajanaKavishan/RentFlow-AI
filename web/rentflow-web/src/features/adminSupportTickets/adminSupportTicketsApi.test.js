import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import {
  getAdminSupportTicket,
  getAdminSupportTickets,
  updateAdminSupportTicketStatus,
} from './adminSupportTicketsApi.js'

const ticket = {
  id: '11111111-1111-1111-1111-111111111111',
  category: 'TechnicalIssue',
  subject: 'Page will not load',
  status: 'Open',
  createdAt: '2026-09-26T10:00:00Z',
  requesterFullName: 'Taylor Tenant',
  requesterEmail: 'taylor@example.com',
}
const detail = {
  ...ticket,
  message: 'The profile page remains in a loading state.',
  updatedAt: '2026-09-26T10:00:00Z',
}
const pagination = {
  page: 2,
  pageSize: 10,
  totalCount: 13,
  totalPages: 2,
  hasNextPage: false,
  hasPreviousPage: true,
}
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'Content-Type': 'application/json' },
})

beforeEach(() => {
  tokenStorage.setToken('admin-session-token')
  vi.stubGlobal('fetch', vi.fn())
})
afterEach(() => { tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('Admin support tickets API', () => {
  it('sends authenticated paging and filter parameters', async () => {
    fetch.mockResolvedValue(json({ items: [ticket], pagination }))

    const result = await getAdminSupportTickets({
      page: 2,
      status: 'Open',
      category: 'TechnicalIssue',
      search: 'Taylor',
    })

    expect(result).toEqual({ items: [ticket], pagination })
    const [input, options] = fetch.mock.calls[0]
    const url = new URL(input, 'http://localhost')
    expect(url.pathname).toBe('/api/admin/support-tickets')
    expect(Object.fromEntries(url.searchParams)).toEqual({
      page: '2',
      pageSize: '10',
      status: 'Open',
      category: 'TechnicalIssue',
      search: 'Taylor',
    })
    expect(options.headers.Authorization).toBe('Bearer admin-session-token')
  })

  it('loads details and PATCHes only the requested forward status', async () => {
    fetch.mockResolvedValueOnce(json(detail)).mockResolvedValueOnce(json({
      id: ticket.id,
      status: 'InProgress',
      updatedAt: '2026-09-26T11:00:00Z',
    }))

    expect(await getAdminSupportTicket(ticket.id)).toEqual(detail)
    expect((await updateAdminSupportTicketStatus(ticket.id, 'InProgress')).status).toBe('InProgress')

    const [detailInput, detailOptions] = fetch.mock.calls[0]
    expect(new URL(detailInput, 'http://localhost').pathname).toBe(`/api/admin/support-tickets/${ticket.id}`)
    expect(detailOptions.headers.Authorization).toBe('Bearer admin-session-token')
    const [updateInput, updateOptions] = fetch.mock.calls[1]
    expect(new URL(updateInput, 'http://localhost').pathname).toBe(`/api/admin/support-tickets/${ticket.id}/status`)
    expect(updateOptions.method).toBe('PATCH')
    expect(JSON.parse(updateOptions.body)).toEqual({ status: 'InProgress' })
    expect(updateOptions.body).not.toContain('userId')
    expect(updateOptions.body).not.toContain('role')
  })

  it('rejects malformed list, detail, and status responses', async () => {
    fetch.mockResolvedValueOnce(json({ items: [{ ...ticket, status: 'Closed' }], pagination }))
      .mockResolvedValueOnce(json({ ...detail, requesterEmail: null }))
      .mockResolvedValueOnce(json({ id: ticket.id, status: 'Resolved' }))

    await expect(getAdminSupportTickets()).rejects.toThrow('invalid Admin support ticket response')
    await expect(getAdminSupportTicket(ticket.id)).rejects.toThrow('invalid Admin support ticket response')
    await expect(updateAdminSupportTicketStatus(ticket.id, 'Resolved')).rejects.toThrow('invalid Admin support ticket response')
  })
})
