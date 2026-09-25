import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../../core/api/apiClient.js'
import { getAdminUserRoleTotals, getAdminUserTotal } from '../../features/adminUsers/adminUsersApi.js'
import { NotificationCountContext } from '../../features/notifications/NotificationCountContext.js'
import AdminDashboard from './AdminDashboard.jsx'

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
  getAdminUserTotal.mockReset().mockResolvedValue(22)
  getAdminUserRoleTotals.mockReset().mockResolvedValue(roleTotals)
})

afterEach(() => cleanup())

describe('Admin dashboard user total', () => {
  it('shows the authorized directory total while leaving unsupported metrics unavailable', async () => {
    getAdminUserTotal.mockResolvedValue(1432)

    renderDashboard()

    const summary = screen.getByRole('region', { name: 'System summary' })
    const totalUsers = within(summary).getByRole('region', { name: 'Total Users' })
    expect(await within(totalUsers).findByText('1,432')).toBeInTheDocument()
    expect(totalUsers).toHaveTextContent('Users in the authorized directory')
    expect(totalUsers).not.toHaveTextContent('Integration pending')
    expect(getAdminUserTotal).toHaveBeenCalledWith({ signal: expect.any(AbortSignal) })

    for (const title of ['Properties', 'Active Applications', 'Monthly Volume']) {
      expect(within(summary).getByRole('region', { name: title })).toHaveTextContent('Integration pending')
    }
    expect(within(summary).getAllByText('Integration pending')).toHaveLength(3)
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
