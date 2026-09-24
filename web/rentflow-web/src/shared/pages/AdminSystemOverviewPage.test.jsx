import { cleanup, render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

vi.mock('../../features/notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))

const account = (role = 'Admin') => ({
  id: '11111111-1111-1111-1111-111111111111', fullName: 'Sam Perera',
  email: 'sam@example.com', phoneNumber: '+94 77 123 4567', role,
})

function renderRoute(role = 'Admin') {
  const session = { user: account(role), isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return render(<MemoryRouter initialEntries={['/modules/ai-system-overview']}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  tokenStorage.setToken('admin-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  vi.stubGlobal('fetch', vi.fn())
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('Admin AI and System Overview page', () => {
  it('renders the two requested pending integration sections without inventing system data', () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'AI / System Overview', level: 1 })).toBeInTheDocument()
    expect(within(main).getByText('Platform administration')).toBeInTheDocument()
    expect(within(main).getByText(/Monitor AI workflows and system reporting/)).toBeInTheDocument()

    const workflows = within(main).getByRole('region', { name: 'AI Workflows' })
    expect(workflows).toHaveTextContent('Integration pending')
    expect(workflows).toHaveTextContent('Admin-authorized aggregate API')
    expect(workflows).toHaveTextContent('Aggregate workflow reporting')
    expect(workflows).toHaveTextContent('No validation outcomes, workflow totals or activity records')

    const health = within(main).getByRole('region', { name: 'System Health' })
    expect(health).toHaveTextContent('Integration pending')
    expect(health).toHaveTextContent('supported monitoring API')
    expect(health).toHaveTextContent('No service statuses, uptime or latency measurements are inferred')
    expect(within(main).getAllByRole('status')).toHaveLength(2)
    expect(fetch).not.toHaveBeenCalled()
  })

  it('omits the removed Figma cards and keeps the overview limited to its two sections', () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getAllByRole('region')).toHaveLength(2)
    expect(main).not.toHaveTextContent('Design principle')
    expect(main).not.toHaveTextContent('Admin essentials')
    expect(main).not.toHaveTextContent('Available now')
    expect(main).not.toHaveTextContent(/AI score|validation result|workflow count|activity log/i)
  })

  it('keeps the route active and preserves the shared Admin navigation and account actions', () => {
    renderRoute()
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    const overviewLink = within(nav).getByRole('link', { name: 'AI / System Overview' })
    expect(overviewLink).toHaveAttribute('href', '/modules/ai-system-overview')
    expect(overviewLink).toHaveAttribute('aria-current', 'page')
    expect(overviewLink).not.toHaveTextContent('Soon')
    expect(within(nav).getByRole('link', { name: 'Dashboard' })).toHaveAttribute('href', '/dashboard')
    expect(within(nav).getByRole('link', { name: 'Users' })).toHaveAttribute('href', '/modules/users')
    expect(within(nav).getByRole('button', { name: 'Logout' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Notifications' })).toHaveAttribute('href', '/notifications')
    expect(screen.getByRole('button', { name: 'Profile for Sam Perera' })).toBeInTheDocument()
  })

  it.each(['Tenant', 'Landlord', 'MaintenanceTechnician'])('blocks %s from the Admin overview route', (role) => {
    renderRoute(role)
    expect(screen.getByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'AI / System Overview' })).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })
})
