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
  return render(<MemoryRouter initialEntries={['/modules/users']}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  tokenStorage.setToken('admin-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  vi.stubGlobal('fetch', vi.fn())
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('Admin Users page', () => {
  it('renders a dedicated, accessible Admin workspace without requesting or inventing users', () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'Users', level: 1 })).toBeInTheDocument()
    expect(within(main).getByText('Administration workspace')).toBeInTheDocument()
    const directory = within(main).getByRole('region', { name: 'User directory' })
    expect(directory).toHaveTextContent('Integration pending')
    expect(directory).toHaveTextContent('Authorized user directory required')
    expect(directory).toHaveTextContent('does not currently expose an Admin-authorized endpoint')
    expect(directory).toHaveTextContent('No user records, role totals, account statuses or activity information')
    expect(fetch).not.toHaveBeenCalled()
  })

  it('keeps Users active and preserves real shared navigation', () => {
    renderRoute()
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    const usersLink = within(nav).getByRole('link', { name: 'Users' })
    expect(usersLink).toHaveAttribute('href', '/modules/users')
    expect(usersLink).toHaveAttribute('aria-current', 'page')
    expect(usersLink).not.toHaveTextContent('Soon')

    const main = screen.getByRole('main')
    expect(within(main).getByRole('link', { name: 'Back to dashboard' })).toHaveAttribute('href', '/dashboard')
    expect(within(main).getAllByRole('link', { name: /notification/i }).every((link) => link.getAttribute('href') === '/notifications')).toBe(true)
    expect(within(main).getByRole('link', { name: /Profile/ })).toHaveAttribute('href', '/profile')
  })

  it('shows only the real integration state and no unsupported user controls', () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('status')).toHaveTextContent('Integration pending')
    expect(within(main).queryByRole('button')).not.toBeInTheDocument()
    expect(main).not.toHaveTextContent(/add user|edit role|disable account|delete user/i)
    expect(main).not.toHaveTextContent(/loading users|no users|could not load|try again/i)
    expect(main).toHaveTextContent('/api/auth/me')
  })

  it.each(['Tenant', 'Landlord', 'MaintenanceTechnician'])('blocks %s from the Admin Users route', (role) => {
    renderRoute(role)
    expect(screen.getByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Users' })).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })
})
