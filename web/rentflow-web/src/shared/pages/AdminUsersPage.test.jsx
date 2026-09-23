import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

vi.mock('../../features/notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))

const setupToken = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG'
const account = (role = 'Admin') => ({
  id: '11111111-1111-1111-1111-111111111111', fullName: 'Sam Perera',
  email: 'sam@example.com', phoneNumber: '+94 77 123 4567', role,
})
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
})

function renderRoute(role = 'Admin') {
  const session = { user: account(role), isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return render(<MemoryRouter initialEntries={['/modules/users']}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

async function fillForm() {
  await userEvent.type(screen.getByLabelText('Full name'), 'Taylor Technician')
  await userEvent.type(screen.getByLabelText('Email'), 'tech@example.com')
  await userEvent.type(screen.getByLabelText('Phone number'), '+94770000001')
}

beforeEach(() => {
  tokenStorage.setToken('admin-token')
  localStorage.clear()
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  vi.stubGlobal('fetch', vi.fn())
  Object.defineProperty(navigator, 'clipboard', {
    configurable: true,
    value: { writeText: vi.fn().mockResolvedValue(undefined) },
  })
})
afterEach(() => {
  cleanup()
  tokenStorage.clearToken()
  localStorage.clear()
  vi.unstubAllGlobals()
  delete navigator.clipboard
})

describe('Admin Users page', () => {
  it('shows real Technician creation and honest directory limitations', () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'Users', level: 1 })).toBeInTheDocument()
    expect(within(main).getByRole('region', { name: 'Add Technician' })).toHaveTextContent('Creation available')
    const directory = within(main).getByRole('region', { name: 'User directory' })
    expect(directory).toHaveTextContent('Integration pending')
    expect(directory).toHaveTextContent('Technician creation is available')
    expect(directory).toHaveTextContent('does not expose an Admin-authorized user directory')
    expect(directory).toHaveTextContent('No user list, account counts')
    expect(fetch).not.toHaveBeenCalled()
  })

  it('submits the backend contract and displays a copyable one-time setup link', async () => {
    fetch.mockResolvedValue(json({
      id: '22222222-2222-2222-2222-222222222222',
      fullName: 'Taylor Technician',
      email: 'tech@example.com',
      phoneNumber: '+94770000001',
      role: 'MaintenanceTechnician',
      isActive: false,
      passwordSetupToken: setupToken,
      passwordSetupExpiresAt: '2026-09-23T16:00:00Z',
    }, 201))
    renderRoute()
    await fillForm()

    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))

    expect(await screen.findByRole('heading', { name: 'Securely deliver the setup link' })).toBeInTheDocument()
    const [url, options] = fetch.mock.calls[0]
    expect(new URL(url, 'http://localhost').pathname).toBe('/api/admin/maintenance-technicians')
    expect(options.method).toBe('POST')
    expect(options.headers.Authorization).toBe('Bearer admin-token')
    expect(JSON.parse(options.body)).toEqual({
      fullName: 'Taylor Technician',
      email: 'tech@example.com',
      phoneNumber: '+94770000001',
    })
    const setupLink = screen.getByLabelText('One-time password-setup link')
    expect(setupLink.value).toContain(`/setup-password#token=${setupToken}`)
    expect(screen.getByText(/account is inactive/i)).toBeInTheDocument()
    expect(screen.getByText(/No email has been sent/i)).toBeInTheDocument()
    expect(JSON.stringify({ ...sessionStorage })).not.toContain(setupToken)
    expect(JSON.stringify({ ...localStorage })).not.toContain(setupToken)

    await userEvent.click(screen.getByRole('button', { name: 'Copy link' }))
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(setupLink.value)
    expect(await screen.findByRole('status')).toHaveTextContent('Setup link copied')

    await userEvent.click(screen.getByRole('button', { name: 'Clear setup link' }))
    expect(screen.queryByLabelText('One-time password-setup link')).not.toBeInTheDocument()
  })

  it('shows client validation and duplicate-email API errors', async () => {
    renderRoute()
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    expect(screen.getByRole('alert')).toHaveTextContent('full name')
    expect(fetch).not.toHaveBeenCalled()

    await fillForm()
    fetch.mockResolvedValue(json({ detail: 'An account with this email already exists.' }, 409))
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('An account with this email already exists.')
  })

  it.each([
    [401, 'Your Admin session is no longer valid'],
    [403, 'not authorized to add Technicians'],
    [500, 'pending Technician account could not be created'],
  ])('shows a safe API error for status %s', async (status, message) => {
    fetch.mockResolvedValue(json({ detail: status === 500 ? 'server trace' : 'Denied' }, status))
    renderRoute()
    await fillForm()
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(message)
    expect(screen.getByRole('alert')).not.toHaveTextContent('server trace')
  })

  it('shows and disables the loading state while creation is pending', async () => {
    let resolveRequest
    fetch.mockReturnValue(new Promise((resolve) => { resolveRequest = resolve }))
    renderRoute()
    await fillForm()
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    const button = screen.getByRole('button', { name: 'Creating pending account…' })
    expect(button).toBeDisabled()
    resolveRequest(json({
      id: '22222222-2222-2222-2222-222222222222', fullName: 'Taylor Technician',
      email: 'tech@example.com', phoneNumber: '+94770000001', role: 'MaintenanceTechnician',
      isActive: false, passwordSetupToken: setupToken,
      passwordSetupExpiresAt: '2026-09-23T16:00:00Z',
    }, 201))
    await waitFor(() => expect(
      screen.getByRole('button', { name: 'Create pending Technician' }),
    ).toBeEnabled())
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
    expect(within(main).getByRole('link', { name: /Profile/ })).toHaveAttribute('href', '/profile')
  })

  it.each(['Tenant', 'Landlord', 'MaintenanceTechnician'])('blocks %s from the Admin Users route', (role) => {
    renderRoute(role)
    expect(screen.getByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Add Technician' })).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })
})
