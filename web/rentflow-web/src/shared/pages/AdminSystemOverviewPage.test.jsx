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
  vi.stubGlobal('fetch', vi.fn(async (url) => new Response(JSON.stringify(url.endsWith('/workflows')
    ? ['Application validation', 'Pricing analysis', 'Maintenance coordination'].map((name) => ({ name, total: 2, pending: 0, running: 0, awaitingReview: 0, completed: 1, failed: 1 }))
    : { checkedAt: '2026-10-06T10:00:00Z', services: [{ name: 'RentFlow API', status: 'available', detail: 'Responding' }] }), { status: 200, headers: { 'Content-Type': 'application/json' } })))
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('Admin AI and System Overview page', () => {
  it('loads authenticated workflow reporting and live system checks', async () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'AI / System Monitoring Platform', level: 1 })).toBeInTheDocument()
    expect(within(main).getByText(/Recorded workflow runs and current service connectivity/)).toBeInTheDocument()

    const workflows = within(main).getByRole('region', { name: 'AI Workflows' })
    expect(await within(workflows).findByRole('rowheader', { name: 'Application validation' })).toBeInTheDocument()
    expect(within(workflows).getByRole('columnheader', { name: 'Failed' })).toBeInTheDocument()

    const health = within(main).getByRole('region', { name: 'System Health' })
    expect(await within(health).findByText('Available')).toBeInTheDocument()
    expect(within(main).queryByText('Integration pending')).not.toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(2)
    for (const [, options] of fetch.mock.calls) expect(options.headers.Authorization).toBe('Bearer admin-token')
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
    expect(screen.queryByRole('heading', { name: 'AI / System Monitoring Platform' })).not.toBeInTheDocument()
    expect(fetch.mock.calls.some(([url]) => url.includes('/api/admin/dashboard/'))).toBe(false)
  })
})
