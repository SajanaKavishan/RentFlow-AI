import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

vi.mock('../../features/adminUsers/adminUsersApi.js', async (importOriginal) => ({
  ...(await importOriginal()),
  getAdminUserTotal: vi.fn().mockResolvedValue(47),
  getAdminUserRoleTotals: vi.fn().mockResolvedValue({
    Tenant: 24, Landlord: 12, MaintenanceTechnician: 7, Admin: 4,
  }),
}))

const account = (role) => ({
  id: '11111111-1111-1111-1111-111111111111', fullName: 'Sam Perera',
  email: 'sam@example.com', phoneNumber: '+94 77 123 4567', role,
})
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

function renderDashboard(role) {
  const session = { user: account(role), isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return render(<MemoryRouter initialEntries={['/dashboard']}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  tokenStorage.setToken('staff-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  vi.stubGlobal('fetch', vi.fn(() => Promise.resolve(json({ unreadCount: 3 }))))
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('Technician and Admin dashboards', () => {
  it('renders a dedicated Technician workspace with real shared actions and an honest maintenance dependency', async () => {
    renderDashboard('MaintenanceTechnician')
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'Welcome, Sam Perera' })).toBeInTheDocument()
    expect(within(main).getByText('Technician workspace')).toBeInTheDocument()

    const assignedWork = within(main).getByRole('region', { name: 'Assigned Work' })
    expect(assignedWork).toHaveTextContent('Integration pending')
    expect(assignedWork).toHaveTextContent('Maintenance module required')
    expect(within(assignedWork).getByRole('link', { name: /View integration status/ })).toHaveAttribute('href', '/modules/assigned-work')

    expect(await within(main).findByRole('heading', { name: '3 unread notifications' })).toBeInTheDocument()
    expect(within(main).getAllByRole('link', { name: /Notifications|Open notifications/ }).every((link) => link.getAttribute('href') === '/notifications')).toBe(true)
    expect(within(main).getAllByRole('link', { name: /Profile|View profile/ }).every((link) => link.getAttribute('href') === '/profile')).toBe(true)
    expect(fetch).toHaveBeenCalledTimes(1)
    expect(new URL(fetch.mock.calls[0][0], 'http://localhost').pathname).toBe('/api/notifications/unread-count')
    expect(fetch.mock.calls[0][1].headers.Authorization).toBe('Bearer staff-token')

    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    expect(within(nav).getByRole('link', { name: 'Assigned Work' })).not.toHaveTextContent('Soon')
    expect(within(nav).queryByRole('link', { name: /Users/ })).not.toBeInTheDocument()
  })

  it('renders the Admin System Overview with honest summary and reporting dependencies', async () => {
    renderDashboard('Admin')
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'System Overview' })).toBeInTheDocument()
    expect(within(main).queryByText('Administration workspace')).not.toBeInTheDocument()
    expect(within(main).getByText('Platform Administration')).toBeInTheDocument()
    expect(within(main).getByText(/^Overview status as of .+\.$/)).toBeInTheDocument()
    expect(within(main).queryByText(/all metrics are live/i)).not.toBeInTheDocument()
    expect(within(main).queryByText(/Signed in as/)).not.toBeInTheDocument()

    const summary = within(main).getByRole('region', { name: 'System summary' })
    const totalUsers = within(summary).getByRole('region', { name: 'Total Users' })
    expect(await within(totalUsers).findByText('47')).toBeInTheDocument()
    expect(totalUsers).not.toHaveTextContent('Integration pending')
    for (const title of ['Properties', 'Active Applications', 'Monthly Volume']) {
      const card = within(summary).getByRole('region', { name: title })
      expect(card).toHaveTextContent('Integration pending')
      expect(card).toHaveTextContent('Admin')
    }

    const activity = within(main).getByRole('region', { name: 'Platform Activity' })
    const distribution = within(main).getByRole('region', { name: 'User Distribution' })
    const workflows = within(main).getByRole('region', { name: 'AI Workflows' })
    const health = within(main).getByRole('region', { name: 'System Health' })
    expect(activity).toHaveTextContent('Admin activity-feed contract')
    expect(distribution).toHaveTextContent('Counts include active and inactive accounts')
    expect(distribution).toHaveTextContent('Technicians7')
    expect(workflows).toHaveTextContent('Admin AI reporting aggregate')
    expect(health).toHaveTextContent('Admin service-health contract')
    expect([activity, workflows, health].every((panel) => panel.textContent.includes('Integration pending'))).toBe(true)
    expect(distribution).not.toHaveTextContent('Integration pending')

    const quickAccess = within(main).getByRole('navigation', { name: 'Admin quick access' })
    expect(within(main).queryByRole('link', { name: 'Add Technician' })).not.toBeInTheDocument()
    expect(within(quickAccess).getByRole('link', { name: 'Manage Users / Add Technician' })).toHaveAttribute('href', '/modules/users?action=add-technician')
    expect(within(quickAccess).getByRole('link', { name: 'Open notifications from Quick Access' })).toHaveAttribute('href', '/notifications')
    expect(within(quickAccess).getByRole('link', { name: 'Profile' })).toHaveAttribute('href', '/profile')
    expect(within(quickAccess).getByRole('link', { name: 'AI / System Overview' })).toHaveAttribute('href', '/modules/ai-system-overview')
    expect(await within(quickAccess).findByText('3 unread notifications')).toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(1)
    expect(new URL(fetch.mock.calls[0][0], 'http://localhost').pathname).toBe('/api/notifications/unread-count')
    expect(fetch.mock.calls[0][1].headers.Authorization).toBe('Bearer staff-token')
    expect(main).not.toHaveTextContent(/all systems operational|uptime|recent sign-up|AI requests|maintenance jobs/i)

    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    expect(within(nav).getByRole('link', { name: 'Users' })).not.toHaveTextContent('Soon')
    expect(within(nav).getByRole('link', { name: 'AI / System Overview' })).not.toHaveTextContent('Soon')
    expect(within(nav).queryByRole('link', { name: /Assigned Work/ })).not.toBeInTheDocument()
  })

  it('does not present a zero unread count when the authorized count service is unavailable', async () => {
    fetch.mockResolvedValue(json({ message: 'Unavailable' }, 503))
    renderDashboard('Admin')
    expect(await screen.findByText('Unread count unavailable — open the inbox directly')).toBeInTheDocument()
    expect(screen.getByRole('main')).not.toHaveTextContent(/0 unread|no unread/i)
    expect(within(screen.getByRole('main')).getByRole('link', { name: 'Open notifications from Quick Access' })).toHaveAttribute('href', '/notifications')
  })

  it.each([
    ['MaintenanceTechnician', 'Assigned Work', 'Assigned Work', /View integration status/],
    ['Admin', 'AI Workflows', 'AI / System Overview', /View integration details/],
  ])('opens the explicit workspace for %s %s', async (role, label, pageTitle, linkName) => {
    renderDashboard(role)
    const main = screen.getByRole('main')
    const region = within(main).getByRole('region', { name: label })
    await userEvent.click(within(region).getByRole('link', { name: linkName }))
    expect(screen.getByRole('heading', { name: pageTitle })).toBeInTheDocument()
    expect(screen.getAllByText('Integration pending').length).toBeGreaterThan(0)
  })

  it('opens the working Technician provisioning page from Admin Quick Access', async () => {
    fetch.mockImplementation((input) => {
      const path = new URL(input, 'http://localhost').pathname
      return Promise.resolve(path === '/api/admin/users'
        ? json({
          items: [],
          pagination: { page: 1, pageSize: 8, totalCount: 0, totalPages: 0, hasNextPage: false, hasPreviousPage: false },
        })
        : json({ unreadCount: 3 }))
    })
    renderDashboard('Admin')
    const quickAccess = within(screen.getByRole('main')).getByRole('navigation', { name: 'Admin quick access' })
    await userEvent.click(within(quickAccess).getByRole('link', { name: 'Manage Users / Add Technician' }))
    expect(screen.getByRole('heading', { name: 'Users' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Add Technician' })).toBeInTheDocument()
    expect(screen.getByLabelText('Full name')).toHaveFocus()
    expect(await screen.findByText('No users match these filters')).toBeInTheDocument()
    expect(screen.getByText('Directory available')).toBeInTheDocument()
  })

  it('keeps Notifications and Profile reachable from both dedicated dashboards', async () => {
    const view = renderDashboard('MaintenanceTechnician')
    await userEvent.click(within(screen.getByRole('main')).getByRole('link', { name: 'View profile' }))
    expect(screen.getByRole('heading', { name: 'Profile' })).toBeInTheDocument()

    view.unmount()
    fetch.mockImplementation((url) => Promise.resolve(json(url.includes('unread-count')
      ? { unreadCount: 0 }
      : { items: [], pagination: { page: 1, totalPages: 1, totalCount: 0, hasNextPage: false, hasPreviousPage: false } })))
    renderDashboard('Admin')
    await userEvent.click(within(screen.getByRole('main')).getByRole('link', { name: 'Open notifications from Quick Access' }))
    expect(await screen.findByRole('heading', { name: 'Notifications' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'No notifications yet' })).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('link', { name: 'Notifications' })).toBeInTheDocument())
  })
})
