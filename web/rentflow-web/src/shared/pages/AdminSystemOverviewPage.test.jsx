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
  it('renders an accessible integration workspace without requesting or inventing system data', () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'AI & System Overview', level: 1 })).toBeInTheDocument()
    expect(within(main).getByText('Administration workspace')).toBeInTheDocument()
    const overview = within(main).getByRole('region', { name: 'Overview workspace' })
    expect(overview).toHaveTextContent('Integration pending')
    expect(overview).toHaveTextContent('Aggregate Admin reporting required')
    expect(overview).toHaveTextContent('does not currently expose an Admin-authorized aggregate')
    expect(overview).toHaveTextContent('require a known rental application or workflow ID')
    expect(overview).toHaveTextContent('No scores, outcomes, usage metrics, health statuses, charts, activity records or totals')
    expect(fetch).not.toHaveBeenCalled()
  })

  it('keeps the route active and preserves real Admin navigation and account actions', () => {
    renderRoute()
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    const overviewLink = within(nav).getByRole('link', { name: 'AI / System Overview' })
    expect(overviewLink).toHaveAttribute('href', '/modules/ai-system-overview')
    expect(overviewLink).toHaveAttribute('aria-current', 'page')
    expect(overviewLink).not.toHaveTextContent('Soon')
    expect(within(nav).getByRole('link', { name: 'Users' })).toHaveAttribute('href', '/modules/users')
    expect(within(nav).getByRole('button', { name: 'Logout' })).toBeInTheDocument()

    const main = screen.getByRole('main')
    expect(within(main).getByRole('link', { name: 'Back to dashboard' })).toHaveAttribute('href', '/dashboard')
    expect(within(main).getAllByRole('link', { name: /notification/i }).every((link) => link.getAttribute('href') === '/notifications')).toBe(true)
    expect(within(main).getByRole('link', { name: /Profile/ })).toHaveAttribute('href', '/profile')
  })

  it('shows only the applicable pending state and identifies the scoped APIs that cannot back the overview', () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('status')).toHaveTextContent('Integration pending')
    expect(main).toHaveTextContent('/api/rental-applications/{applicationId}/validation-runs')
    expect(main).toHaveTextContent('/api/application-validation-workflows/{workflowId}')
    expect(within(main).queryByRole('button')).not.toBeInTheDocument()
    expect(main).not.toHaveTextContent(/loading overview|no activity|could not load|try again/i)
  })

  it.each(['Tenant', 'Landlord', 'MaintenanceTechnician'])('blocks %s from the Admin overview route', (role) => {
    renderRoute(role)
    expect(screen.getByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'AI & System Overview' })).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })
})
