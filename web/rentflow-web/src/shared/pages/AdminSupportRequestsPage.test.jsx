import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import {
  getAdminSupportTicket,
  getAdminSupportTickets,
  updateAdminSupportTicketStatus,
} from '../../features/adminSupportTickets/adminSupportTicketsApi.js'
import { getUnreadCount } from '../../features/notifications/notificationsApi.js'

vi.mock('../../features/adminSupportTickets/adminSupportTicketsApi.js', () => ({
  ADMIN_SUPPORT_PAGE_SIZE: 10,
  SUPPORT_TICKET_STATUSES: ['Open', 'InProgress', 'Resolved'],
  SUPPORT_TICKET_CATEGORIES: ['TechnicalIssue', 'AccountLogin', 'PropertyApplication', 'Payment', 'Other'],
  getAdminSupportTicket: vi.fn(),
  getAdminSupportTickets: vi.fn(),
  updateAdminSupportTicketStatus: vi.fn(),
}))

vi.mock('../../features/notifications/notificationsApi.js', () => ({
  getUnreadCount: vi.fn(),
  getNotifications: vi.fn(),
  markNotificationRead: vi.fn(),
}))

const openTicket = {
  id: '11111111-1111-1111-1111-111111111111',
  category: 'TechnicalIssue',
  subject: 'Profile page will not load',
  status: 'Open',
  createdAt: '2026-09-26T10:00:00Z',
  requesterFullName: 'Taylor Tenant',
  requesterEmail: 'taylor@example.com',
}
const inProgressTicket = {
  ...openTicket,
  id: '22222222-2222-2222-2222-222222222222',
  category: 'Payment',
  subject: 'Receipt is missing',
  status: 'InProgress',
  requesterFullName: 'Lee Landlord',
  requesterEmail: 'lee@example.com',
}
const resolvedTicket = {
  ...openTicket,
  id: '33333333-3333-3333-3333-333333333333',
  category: 'Other',
  subject: 'Resolved request',
  status: 'Resolved',
}
const pagination = {
  page: 1,
  pageSize: 10,
  totalCount: 3,
  totalPages: 2,
  hasNextPage: true,
  hasPreviousPage: false,
}
const detail = {
  ...openTicket,
  message: 'The page keeps showing a loading spinner.',
  updatedAt: '2026-09-26T10:00:00Z',
}

function page(items = [openTicket, inProgressTicket, resolvedTicket], overrides = {}) {
  return { items, pagination: { ...pagination, totalCount: items.length, ...overrides } }
}

function account(role = 'Admin') {
  return {
    user: { id: 'admin-id', fullName: 'Sam Admin', email: 'sam@example.com', role },
    isAuthenticated: true,
    isLoading: false,
    logout: vi.fn(),
  }
}

function renderRoute(role = 'Admin') {
  return render(<MemoryRouter initialEntries={['/modules/support-requests']}><AuthContext.Provider value={account(role)}><App /></AuthContext.Provider></MemoryRouter>)
}

function deferred() {
  let resolve
  let reject
  const promise = new Promise((onResolve, onReject) => { resolve = onResolve; reject = onReject })
  return { promise, resolve, reject }
}

beforeEach(() => {
  getAdminSupportTickets.mockReset().mockResolvedValue(page())
  getAdminSupportTicket.mockReset().mockResolvedValue(detail)
  updateAdminSupportTicketStatus.mockReset()
  getUnreadCount.mockReset().mockResolvedValue(0)
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
})
afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.restoreAllMocks() })

describe('Admin Support Requests route', () => {
  it('is a real Admin-only navigation destination with valid actions per status', async () => {
    renderRoute()

    expect(await screen.findByRole('heading', { name: 'Support Requests' })).toBeInTheDocument()
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    expect(within(nav).getByRole('link', { name: 'Support Requests' })).toHaveAttribute('aria-current', 'page')

    const openRow = screen.getByRole('row', { name: /Profile page will not load/ })
    expect(openRow).toHaveTextContent('Taylor Tenant')
    expect(openRow).toHaveTextContent('taylor@example.com')
    expect(within(openRow).getByRole('button', { name: 'Mark In Progress' })).toBeEnabled()
    expect(within(openRow).getByRole('button', { name: 'Resolve' })).toBeEnabled()

    const progressRow = screen.getByRole('row', { name: /Receipt is missing/ })
    expect(within(progressRow).queryByRole('button', { name: 'Mark In Progress' })).not.toBeInTheDocument()
    expect(within(progressRow).getByRole('button', { name: 'Resolve' })).toBeEnabled()

    const resolvedRow = screen.getByRole('row', { name: /Resolved request/ })
    expect(within(resolvedRow).getByRole('button', { name: 'View' })).toBeEnabled()
    expect(within(resolvedRow).queryByRole('button', { name: 'Resolve' })).not.toBeInTheDocument()
  })

  it.each(['Tenant', 'Landlord', 'MaintenanceTechnician'])('blocks %s from the route and navigation', (role) => {
    renderRoute(role)

    expect(screen.getByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Support Requests' })).not.toBeInTheDocument()
    expect(getAdminSupportTickets).not.toHaveBeenCalled()
  })

  it('sends status, category, search, and pagination controls to the API', async () => {
    renderRoute()
    await screen.findByText('Profile page will not load')

    await userEvent.click(screen.getByRole('button', { name: 'In Progress', pressed: false }))
    await waitFor(() => expect(getAdminSupportTickets).toHaveBeenLastCalledWith(expect.objectContaining({ status: 'InProgress', page: 1 })))

    await userEvent.selectOptions(screen.getByLabelText('Category'), 'Payment')
    await waitFor(() => expect(getAdminSupportTickets).toHaveBeenLastCalledWith(expect.objectContaining({ category: 'Payment', page: 1 })))

    await userEvent.type(screen.getByLabelText('Search'), 'Lee')
    await userEvent.click(screen.getByRole('button', { name: 'Search' }))
    await waitFor(() => expect(getAdminSupportTickets).toHaveBeenLastCalledWith(expect.objectContaining({ search: 'Lee', page: 1 })))

    await userEvent.click(screen.getByRole('button', { name: 'Next' }))
    await waitFor(() => expect(getAdminSupportTickets).toHaveBeenLastCalledWith(expect.objectContaining({ page: 2 })))
  })

  it('loads real details and changes status only after API confirmation', async () => {
    const confirmation = deferred()
    updateAdminSupportTicketStatus.mockReturnValue(confirmation.promise)
    renderRoute()
    const openRow = await screen.findByRole('row', { name: /Profile page will not load/ })
    await userEvent.click(within(openRow).getByRole('button', { name: 'View' }))

    const dialog = await screen.findByRole('dialog', { name: 'Profile page will not load' })
    expect(within(dialog).getByText(detail.message)).toBeInTheDocument()
    expect(within(dialog).getByText('taylor@example.com')).toBeInTheDocument()
    await userEvent.click(within(dialog).getByRole('button', { name: 'Mark In Progress' }))

    expect(updateAdminSupportTicketStatus).toHaveBeenCalledWith(openTicket.id, 'InProgress')
    expect(within(dialog).getByRole('button', { name: 'Updating…' })).toBeDisabled()
    expect(within(openRow).getByText('Open')).toBeInTheDocument()
    expect(within(dialog).getByText('Open')).toBeInTheDocument()

    await act(async () => confirmation.resolve({
      id: openTicket.id,
      status: 'InProgress',
      updatedAt: '2026-09-26T11:00:00Z',
    }))
    expect(within(openRow).getByText('In Progress')).toBeInTheDocument()
    expect(within(dialog).getByText('In Progress')).toBeInTheDocument()
    expect(within(dialog).queryByRole('button', { name: 'Mark In Progress' })).not.toBeInTheDocument()
  })

  it('keeps the confirmed status unchanged when an update fails', async () => {
    updateAdminSupportTicketStatus.mockRejectedValue(new Error('Status service unavailable.'))
    renderRoute()
    const openRow = await screen.findByRole('row', { name: /Profile page will not load/ })

    await userEvent.click(within(openRow).getByRole('button', { name: 'Resolve' }))

    expect(await within(openRow).findByRole('alert')).toHaveTextContent('Status service unavailable.')
    expect(within(openRow).getByText('Open')).toBeInTheDocument()
    expect(within(openRow).getByRole('button', { name: 'Resolve' })).toBeEnabled()
  })

  it('shows loading, error, retry, and empty states without stale ticket rows', async () => {
    const firstRequest = deferred()
    getAdminSupportTickets.mockReturnValueOnce(firstRequest.promise).mockResolvedValueOnce(page([], {
      totalCount: 0, totalPages: 0, hasNextPage: false,
    }))
    renderRoute()

    expect(screen.getByRole('status')).toHaveTextContent('Loading support requests')
    await act(async () => firstRequest.reject(new Error('Queue unavailable.')))
    expect(await screen.findByRole('alert')).toHaveTextContent('Queue unavailable.')
    expect(screen.queryByText('Profile page will not load')).not.toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByRole('heading', { name: 'No support requests found' })).toBeInTheDocument()
  })
})
