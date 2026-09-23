import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AssignedWorkState } from './TechnicianAssignedWorkPage.jsx'

vi.mock('../../features/notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))

const account = (role = 'MaintenanceTechnician') => ({
  id: '11111111-1111-1111-1111-111111111111', fullName: 'Sam Perera',
  email: 'sam@example.com', phoneNumber: '+94 77 123 4567', role,
})

function renderRoute(role = 'MaintenanceTechnician') {
  const session = { user: account(role), isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return render(<MemoryRouter initialEntries={['/modules/assigned-work']}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  tokenStorage.setToken('technician-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  vi.stubGlobal('fetch', vi.fn())
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('Technician Assigned Work page', () => {
  it('renders a dedicated, accessible Technician work area without requesting or inventing maintenance records', () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'Assigned Work', level: 1 })).toBeInTheDocument()
    expect(within(main).getByText('Technician workspace')).toBeInTheDocument()
    const workArea = within(main).getByRole('region', { name: 'Your work queue' })
    expect(workArea).toHaveTextContent('Integration pending')
    expect(workArea).toHaveTextContent('Work queue integration required')
    expect(workArea).toHaveTextContent('does not currently provide an authenticated collection')
    expect(workArea).not.toHaveTextContent(/\b[0-9]+ (jobs|requests|assignments)\b/i)
    expect(fetch).not.toHaveBeenCalled()
  })

  it('keeps navigation active and exposes only real shared destinations', () => {
    renderRoute()
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    const assignedLink = within(nav).getByRole('link', { name: 'Assigned Work' })
    expect(assignedLink).toHaveAttribute('href', '/modules/assigned-work')
    expect(assignedLink).toHaveAttribute('aria-current', 'page')
    expect(assignedLink).not.toHaveTextContent('Soon')

    const main = screen.getByRole('main')
    expect(within(main).getByRole('link', { name: 'Back to dashboard' })).toHaveAttribute('href', '/dashboard')
    expect(within(main).getAllByRole('link', { name: /notification/i }).every((link) => link.getAttribute('href') === '/notifications')).toBe(true)
    expect(within(main).getByRole('link', { name: /Profile/ })).toHaveAttribute('href', '/profile')
    expect(within(main).queryByRole('button', { name: /estimate|start|complete/i })).not.toBeInTheDocument()
  })

  it.each(['Tenant', 'Landlord', 'Admin'])('blocks %s from the Technician route', (role) => {
    renderRoute(role)
    expect(screen.getByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Assigned Work' })).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })

  it('provides accessible loading and empty presentations for the future collection workflow', () => {
    const view = render(<AssignedWorkState status="loading" />)
    expect(screen.getByRole('status')).toHaveAttribute('aria-busy', 'true')
    expect(screen.getByRole('heading', { name: 'Loading assigned work' })).toBeInTheDocument()

    view.rerender(<AssignedWorkState status="empty" />)
    expect(screen.getByRole('heading', { name: 'No assigned work' })).toBeInTheDocument()
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('provides an accessible retryable error presentation without manufacturing records', async () => {
    const retry = vi.fn()
    render(<AssignedWorkState status="error" error="Unable to reach assigned work." onRetry={retry} />)
    expect(screen.getByRole('alert')).toHaveTextContent('Unable to reach assigned work.')
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(retry).toHaveBeenCalledOnce()
  })
})
