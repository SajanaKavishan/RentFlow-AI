import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

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
    expect(within(nav).getByRole('link', { name: /Assigned Work/ })).toHaveTextContent('Soon')
    expect(within(nav).queryByRole('link', { name: /Users/ })).not.toBeInTheDocument()
  })

  it('renders a distinct Admin management layout without invented management or system data', async () => {
    renderDashboard('Admin')
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'Welcome, Sam Perera' })).toBeInTheDocument()
    expect(within(main).getByText('Administration workspace')).toBeInTheDocument()
    expect(within(main).getByText('No user, AI or system totals are available from the current web APIs.')).toBeInTheDocument()

    const users = within(main).getByRole('region', { name: 'Users' })
    const system = within(main).getByRole('region', { name: 'AI / System Overview' })
    expect(users).toHaveTextContent('Authorized user-management API and owning module')
    expect(system).toHaveTextContent('System-overview API contract and owning module')
    expect(within(users).getByRole('link', { name: /View integration status/ })).toHaveAttribute('href', '/modules/users')
    expect(within(system).getByRole('link', { name: /View integration status/ })).toHaveAttribute('href', '/modules/ai-system-overview')
    expect(await within(main).findByRole('heading', { name: '3 unread notifications' })).toBeInTheDocument()
    expect(within(main).getAllByRole('link', { name: /Notifications|Open notifications|Review notifications/ }).every((link) => link.getAttribute('href') === '/notifications')).toBe(true)
    expect(within(main).getByRole('link', { name: /Profile/ })).toHaveAttribute('href', '/profile')
    expect(main).not.toHaveTextContent(/active users|system health|AI requests|maintenance jobs/i)

    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    expect(within(nav).getByRole('link', { name: /Users/ })).toHaveTextContent('Soon')
    expect(within(nav).getByRole('link', { name: /AI \/ System Overview/ })).toHaveTextContent('Soon')
    expect(within(nav).queryByRole('link', { name: /Assigned Work/ })).not.toBeInTheDocument()
  })

  it('does not present a zero unread count when the authorized count service is unavailable', async () => {
    fetch.mockResolvedValue(json({ message: 'Unavailable' }, 503))
    renderDashboard('Admin')
    expect(await screen.findByRole('heading', { name: 'Notification count unavailable' })).toBeInTheDocument()
    expect(screen.getByRole('main')).not.toHaveTextContent(/0 unread|no unread/i)
    expect(screen.getByRole('link', { name: /Open notifications/ })).toHaveAttribute('href', '/notifications')
  })

  it.each([
    ['MaintenanceTechnician', 'Assigned Work'],
    ['Admin', 'Users'],
    ['Admin', 'AI / System Overview'],
  ])('opens the explicit integration status for %s %s', async (role, label) => {
    renderDashboard(role)
    const main = screen.getByRole('main')
    const region = within(main).getByRole('region', { name: label })
    await userEvent.click(within(region).getByRole('link', { name: /View integration status/ }))
    expect(screen.getByRole('heading', { name: label })).toBeInTheDocument()
    expect(screen.getByText('Integration pending')).toBeInTheDocument()
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
    await userEvent.click(within(screen.getByRole('main')).getByRole('link', { name: 'Review notifications' }))
    expect(await screen.findByRole('heading', { name: 'Notifications' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'No notifications yet' })).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('link', { name: 'Notifications' })).toBeInTheDocument())
  })
})
