import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../../core/api/apiClient.js'
import { getAdminUserRoleTotals, getAdminUserTotal } from '../../features/adminUsers/adminUsersApi.js'
import { NotificationCountContext } from '../../features/notifications/NotificationCountContext.js'
import AdminDashboard from './AdminDashboard.jsx'
import { getAdminActivityPage, getAdminReport } from './adminReportingApi.js'
vi.mock('./adminReportingApi.js', () => ({ getAdminReport: vi.fn(), getAdminActivityPage: vi.fn() }))

const reports = {
  summary: { propertyCount: 9, activeApplicationCount: 4, monthlyVolume: 250000, month: '2026-10' },
  activity: [{ kind: 'Property listed', description: 'Garden home', occurredAt: '2026-10-06T10:00:00Z' }],
  workflows: [{ name: 'Application validation', total: 5, pending: 1, running: 0, awaitingReview: 1, completed: 2, failed: 1 }],
  health: { checkedAt: '2026-10-06T10:00:00Z', services: [{ name: 'Database', status: 'available', detail: 'Connectivity checked' }, { name: 'AI agent', status: 'unavailable', detail: 'Endpoint unreachable' }] },
}

vi.mock('../../features/adminUsers/adminUsersApi.js', () => ({
  ADMIN_USER_DISTRIBUTION_ROLES: ['Tenant', 'Landlord', 'MaintenanceTechnician', 'Admin'],
  getAdminUserRoleTotals: vi.fn(),
  getAdminUserTotal: vi.fn(),
}))

const admin = (id = 'admin-one') => ({ id, fullName: 'Sam Admin', role: 'Admin' })
const roleTotals = { Tenant: 12, Landlord: 5, MaintenanceTechnician: 3, Admin: 2 }

function deferred() {
  let resolve
  let reject
  const promise = new Promise((resolvePromise, rejectPromise) => {
    resolve = resolvePromise
    reject = rejectPromise
  })
  return { promise, resolve, reject }
}

function dashboard(user) {
  return (
    <MemoryRouter>
      <NotificationCountContext.Provider value={{ unreadCount: 2, countStatus: 'ready' }}>
        <AdminDashboard user={user} />
      </NotificationCountContext.Provider>
    </MemoryRouter>
  )
}

function renderDashboard(user = admin()) {
  return render(dashboard(user))
}

beforeEach(() => {
  getAdminActivityPage.mockReset().mockResolvedValue([])
  getAdminReport.mockReset().mockImplementation(async (kind) => reports[kind])
  getAdminUserTotal.mockReset().mockResolvedValue(22)
  getAdminUserRoleTotals.mockReset().mockResolvedValue(roleTotals)
})

afterEach(() => cleanup())

describe('Admin dashboard user total', () => {
  it('shows authorized directory totals and live platform metrics', async () => {
    getAdminUserTotal.mockResolvedValue(1432)

    renderDashboard()

    const summary = screen.getByRole('region', { name: 'System summary' })
    const totalUsers = within(summary).getByRole('region', { name: 'Total Users' })
    expect(await within(totalUsers).findByText('1,432')).toBeInTheDocument()
    expect(totalUsers).toHaveTextContent('Users in the authorized directory')
    expect(totalUsers).not.toHaveTextContent('Integration pending')
    expect(getAdminUserTotal).toHaveBeenCalledWith({ signal: expect.any(AbortSignal) })

    expect(await within(within(summary).getByRole('region', { name: 'Properties' })).findByText('9')).toBeInTheDocument()
    expect(within(summary).getByRole('region', { name: 'Active Applications' })).toHaveTextContent('4')
    expect(within(summary).getByRole('region', { name: 'Monthly Volume' })).toHaveTextContent('Rs. 250,000')
    expect(screen.queryByText('Integration pending')).not.toBeInTheDocument()
  })

  it('shows a loading state without presenting a fabricated count', () => {
    getAdminUserTotal.mockReturnValue(new Promise(() => {}))

    renderDashboard()

    const card = screen.getByRole('region', { name: 'Total Users' })
    expect(card).toHaveAttribute('aria-busy', 'true')
    expect(within(card).getByRole('status')).toHaveTextContent('Loading total users')
    expect(within(card).queryByText(/^0$/)).not.toBeInTheDocument()
  })

  it('keeps the total unavailable while retrying and after an API error', async () => {
    const retryRequest = deferred()
    getAdminUserTotal
      .mockRejectedValueOnce(new ApiError('The user directory could not be loaded.', 503))
      .mockReturnValueOnce(retryRequest.promise)

    renderDashboard()
    const card = screen.getByRole('region', { name: 'Total Users' })
    expect(await within(card).findByRole('alert')).toHaveTextContent('The user directory could not be loaded.')
    expect(within(card).queryByText(/^0$/)).not.toBeInTheDocument()

    await userEvent.click(within(card).getByRole('button', { name: 'Retry total users' }))
    await waitFor(() => expect(within(card).getByRole('status')).toBeInTheDocument())
    expect(within(card).queryByText(/^0$/)).not.toBeInTheDocument()

    await act(async () => retryRequest.reject(new ApiError('The user directory could not be loaded.', 503)))
    expect(await within(card).findByRole('alert')).toHaveTextContent('The user directory could not be loaded.')
    expect(within(card).queryByText(/^0$/)).not.toBeInTheDocument()
  })

  it.each([
    [401, 'session is no longer valid'],
    [403, 'not authorized'],
  ])('shows an authorization-safe state for a %s response', async (status, message) => {
    getAdminUserTotal.mockRejectedValue(new ApiError('Request failed.', status))

    renderDashboard()

    const card = screen.getByRole('region', { name: 'Total Users' })
    expect(await within(card).findByRole('alert')).toHaveTextContent(message)
    expect(within(card).queryByRole('button', { name: 'Retry total users' })).not.toBeInTheDocument()
    expect(within(card).queryByText(/^0$/)).not.toBeInTheDocument()
  })
})

describe('Admin dashboard user distribution', () => {
  it('previews the newest seven activity entries and expands the selected feed with Show less', async () => {
    const activity = Array.from({ length: 15 }, (_, index) => ({ ...reports.activity[0], description: `Activity ${index + 1}` }))
    getAdminReport.mockImplementation(async (kind) => kind === 'activity' ? activity.slice(0, 10) : reports[kind])
    getAdminActivityPage.mockResolvedValue(activity)
    renderDashboard()
    const panel = screen.getByRole('region', { name: 'Platform Activity' })
    expect(await within(panel).findByText('Activity 7')).toBeInTheDocument()
    expect(within(panel).getAllByRole('listitem')).toHaveLength(7)
    expect(within(panel).queryByText('Activity 8')).not.toBeInTheDocument()
    expect(getAdminActivityPage).not.toHaveBeenCalled()
    await userEvent.click(within(panel).getByRole('button', { name: 'See all' }))
    expect(await within(panel).findByText('Activity 15')).toBeInTheDocument()
    expect(within(panel).getByRole('region', { name: 'All platform activity' })).toBeInTheDocument()
    expect(getAdminActivityPage).toHaveBeenCalledWith(1, expect.any(AbortSignal))
    await userEvent.click(within(panel).getByRole('button', { name: 'Show less' }))
    expect(within(panel).getAllByRole('listitem')).toHaveLength(7)
    expect(within(panel).queryByText('Activity 8')).not.toBeInTheDocument()
  })

  it('loads more activity beyond the first expanded page', async () => {
    const activity = Array.from({ length: 50 }, (_, index) => ({ ...reports.activity[0], description: `Activity ${index + 1}` }))
    getAdminReport.mockImplementation(async (kind) => kind === 'activity' ? activity.slice(0, 10) : reports[kind])
    getAdminActivityPage.mockResolvedValueOnce(activity).mockResolvedValueOnce([{ ...activity[0], description: 'Older activity' }])
    renderDashboard()
    const panel = screen.getByRole('region', { name: 'Platform Activity' })
    await userEvent.click(await within(panel).findByRole('button', { name: 'See all' }))
    await userEvent.click(await within(panel).findByRole('button', { name: 'Load more' }))
    expect(await within(panel).findByText('Older activity')).toBeInTheDocument()
    expect(within(panel).getAllByRole('listitem')).toHaveLength(51)
    expect(within(panel).queryByRole('button', { name: 'Load more' })).not.toBeInTheDocument()
  })

  it('omits See all when the preview includes the whole feed', async () => {
    renderDashboard()
    const panel = screen.getByRole('region', { name: 'Platform Activity' })
    await within(panel).findByText('Garden home')
    expect(within(panel).queryByRole('button', { name: 'See all' })).not.toBeInTheDocument()
  })
  it('shows actual activity, workflow outcomes and unavailable service health', async () => {
    renderDashboard()
    expect(await screen.findByText('Garden home')).toBeInTheDocument()
    const workflows = screen.getByRole('region', { name: 'AI Workflows' })
    expect(await within(workflows).findByRole('rowheader', { name: 'Application validation' })).toBeInTheDocument()
    const health = screen.getByRole('region', { name: 'System Health' })
    expect(await within(health).findByText('Unavailable')).toBeInTheDocument()
    expect(within(health).getByText('Endpoint unreachable')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Open workflow monitor' })).toHaveAttribute('href', '/modules/ai-system-overview')
  })

  it('retries a failed report independently without showing fabricated zero metrics', async () => {
    let attempts = 0
    getAdminReport.mockImplementation(async (kind) => {
      if (kind === 'summary' && attempts++ === 0) throw new Error('Unavailable')
      return reports[kind]
    })
    renderDashboard()
    const properties = screen.getByRole('region', { name: 'Properties' })
    expect(await within(properties).findByRole('alert')).toBeInTheDocument()
    expect(within(properties).queryByText('0')).not.toBeInTheDocument()
    await userEvent.click(within(properties).getByRole('button', { name: 'Try again' }))
    expect(await within(properties).findByText('9')).toBeInTheDocument()
  })

  it('discards old reporting responses when the Admin identity changes', async () => {
    const old = deferred()
    let calls = 0
    getAdminReport.mockImplementation((kind) => kind === 'summary' && calls++ === 0 ? old.promise : Promise.resolve(reports[kind]))
    const view = renderDashboard(admin('old-admin'))
    view.rerender(dashboard(admin('new-admin')))
    const properties = screen.getByRole('region', { name: 'Properties' })
    expect(await within(properties).findByText('9')).toBeInTheDocument()
    await act(async () => old.resolve({ ...reports.summary, propertyCount: 999 }))
    expect(within(properties).queryByText('999')).not.toBeInTheDocument()
  })
  it('renders validated role counts and proportions against the real total', async () => {
    getAdminUserTotal.mockResolvedValue(20)
    getAdminUserRoleTotals.mockResolvedValue({
      Tenant: 10, Landlord: 5, MaintenanceTechnician: 3, Admin: 2,
    })

    renderDashboard()

    const panel = screen.getByRole('region', { name: 'User Distribution' })
    expect(await within(panel).findByText('Live directory')).toBeInTheDocument()
    expect(panel).toHaveTextContent('Counts include active and inactive accounts')
    const expected = [
      ['Tenant', '10', '50%'],
      ['Landlord', '5', '25%'],
      ['Technicians', '3', '15%'],
      ['Admin', '2', '10%'],
    ]
    for (const [label, count, width] of expected) {
      const group = within(panel).getByRole('group', { name: `${label} users` })
      expect(within(group).getByText(label)).toBeInTheDocument()
      expect(within(group).getByText(count)).toBeInTheDocument()
      expect(within(group).getByRole('progressbar', { name: `${label} proportion` }).firstElementChild).toHaveStyle({ width })
    }
    expect(getAdminUserRoleTotals).toHaveBeenCalledWith({ signal: expect.any(AbortSignal) })
  })

  it('shows loading and API failures without displaying role counts as zero', async () => {
    const request = deferred()
    getAdminUserRoleTotals.mockReturnValue(request.promise)
    renderDashboard()

    const panel = screen.getByRole('region', { name: 'User Distribution' })
    expect(within(panel).getByRole('status')).toHaveTextContent('Loading user distribution')
    expect(within(panel).queryByText(/^0$/)).not.toBeInTheDocument()

    await act(async () => request.reject(new ApiError('The user directory could not be loaded.', 503)))
    expect(await within(panel).findByRole('alert')).toHaveTextContent('The user directory could not be loaded.')
    expect(within(panel).queryByText(/^0$/)).not.toBeInTheDocument()
    expect(within(panel).getByRole('button', { name: 'Retry user distribution' })).toBeInTheDocument()
  })

  it.each([
    [401, 'session is no longer valid'],
    [403, 'not authorized'],
  ])('shows an authorization-safe distribution state for a %s response', async (status, message) => {
    getAdminUserRoleTotals.mockRejectedValue(new ApiError('Request failed.', status))

    renderDashboard()

    const panel = screen.getByRole('region', { name: 'User Distribution' })
    expect(await within(panel).findByRole('alert')).toHaveTextContent(message)
    expect(within(panel).queryByRole('button', { name: 'Retry user distribution' })).not.toBeInTheDocument()
    expect(within(panel).queryByText(/^0$/)).not.toBeInTheDocument()
  })

  it('hides old counts and ignores stale responses when the authenticated identity changes', async () => {
    const oldRequest = deferred()
    getAdminUserTotal.mockResolvedValueOnce(22).mockResolvedValueOnce(4)
    getAdminUserRoleTotals
      .mockReturnValueOnce(oldRequest.promise)
      .mockResolvedValueOnce({ Tenant: 1, Landlord: 1, MaintenanceTechnician: 1, Admin: 1 })

    const view = renderDashboard(admin('admin-one'))
    const panel = screen.getByRole('region', { name: 'User Distribution' })
    view.rerender(dashboard(admin('admin-two')))

    expect(within(panel).getByRole('status')).toHaveTextContent('Loading user distribution')
    const tenantGroup = await within(panel).findByRole('group', { name: 'Tenant users' })
    expect(within(tenantGroup).getByText('1')).toBeInTheDocument()

    await act(async () => oldRequest.resolve({ Tenant: 17, Landlord: 3, MaintenanceTechnician: 1, Admin: 1 }))
    expect(within(panel).queryByText('17')).not.toBeInTheDocument()
    expect(getAdminUserRoleTotals).toHaveBeenCalledTimes(2)
  })
})
